defmodule AgenticAiAgent.Agent.Runtime do
  @moduledoc """
  Per-run ReAct loop with queued tool dispatch, risk-gated approvals (HITL),
  and sub-agent delegation. Each run owns its `Run` row, drives the state
  machine `:idle → :planning → :acting → :observing → :reflecting →
  :awaiting_approval? → :done|:failed`, emits telemetry, persists every step,
  and pushes progress messages both to a subscriber pid and to a PubSub
  topic so views and approval UIs can subscribe.

  Tool calls returned by one LLM turn are processed sequentially from a
  queue. Three branches can pause the queue:

    * `delegate` — spawn an isolated sub-agent runtime; resume when its
      `:final` event arrives.
    * risk-gated tool — create an `Approval` row and wait for an external
      `approve/deny/revise` decision.
    * normal — execute immediately via `Tools.Registry`.

  The runtime registers itself in `AgenticAiAgent.Agent.Registry` keyed by
  `run_id` so decisions can be routed back without holding a pid.
  """

  use GenServer

  alias AgenticAiAgent.{Conversation, Failures, Skills, Traces}
  alias AgenticAiAgent.Agent.{Context, Judge, Reflexion, ToT, Workflow}
  alias AgenticAiAgent.LLM.{Adapter, Pricing, Response}
  alias AgenticAiAgent.Tools.Registry, as: ToolRegistry

  @default_max_steps 12

  @pubsub AgenticAiAgent.PubSub
  @runs_topic "runs"
  @registry AgenticAiAgent.Agent.Registry

  # ----- Topics -----

  def topic(run_id), do: "run:#{run_id}"
  def runs_topic, do: @runs_topic

  # ----- Client -----

  def start(opts) do
    DynamicSupervisor.start_child(
      AgenticAiAgent.Agent.RuntimeSupervisor,
      {__MODULE__, opts}
    )
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Approve the pending tool call; runtime executes it as-is."
  def approve(run_id, approval_id, opts \\ []),
    do: cast(run_id, {:decision, approval_id, :approve, opts})

  @doc "Deny the pending tool call; runtime injects a denial tool-result and continues."
  def deny(run_id, approval_id, reason \\ "denied by user"),
    do: cast(run_id, {:decision, approval_id, :deny, [reason: reason]})

  @doc "Approve but with a revised input — runtime runs the tool with the new arguments."
  def revise(run_id, approval_id, new_input),
    do: cast(run_id, {:decision, approval_id, :revise, [input: new_input]})

  @doc """
  Interrupt a running agent with a guidance message. The current pending
  tool queue is dropped, the guidance is appended to the conversation as a
  user message tagged `[STEERING]`, and the planner re-runs on the next tick.
  """
  def steer(run_id, guidance) when is_binary(guidance),
    do: cast(run_id, {:steer, guidance})

  @doc "Cancel a running agent; the run ends with status `cancelled`."
  def cancel(run_id), do: cast(run_id, :cancel)

  defp cast(run_id, msg) do
    case Registry.lookup(@registry, run_id) do
      [{pid, _}] -> GenServer.cast(pid, msg)
      [] -> {:error, :not_found}
    end
  end

  # ----- Server -----

  @impl true
  def init(opts) do
    conv = Keyword.fetch!(opts, :conversation)
    card = Keyword.get(opts, :card)
    user_input = Keyword.fetch!(opts, :user_input)
    subscriber = Keyword.get(opts, :subscriber, self())
    max_steps = Keyword.get(opts, :max_steps, max_steps_from_card(card) || @default_max_steps)
    parent_run_id = Keyword.get(opts, :parent_run_id)
    skill_slug = Keyword.get(opts, :skill_slug)
    tools_allow = Keyword.get(opts, :tools_allow)

    started_at = DateTime.utc_now()

    run =
      Traces.create_run!(%{
        agentic_card_id: card && card.id,
        parent_run_id: parent_run_id,
        skill_slug: skill_slug,
        user_input: user_input,
        status: "running",
        started_at: started_at
      })

    {:ok, _} = Registry.register(@registry, run.id, nil)

    :telemetry.execute(
      [:agent, :run, :start],
      %{system_time: System.system_time()},
      %{run_id: run.id, card_slug: card && card.slug, parent_run_id: parent_run_id}
    )

    broadcast_started(run, card, subscriber)

    :ok = Conversation.append_user(conv, user_input)

    state = %{
      run: run,
      card: card,
      conversation: conv,
      subscriber: subscriber,
      status: :idle,
      iteration: 0,
      max_steps: max_steps,
      started_at: started_at,
      pending_tool_calls: [],
      pending_approval: nil,
      pending_delegate: nil,
      tools_allow: tools_allow,
      workflow: Workflow.from_card(card),
      # ↓ Planning/Reflection extensions (§4)
      reflexion_count: 0,
      reflexion_note: nil,
      tot_note: nil
    }

    {:ok, state, {:continue, :tick}}
  end

  # ----- Loop driver -----

  @impl true
  def handle_continue(:tick, state), do: tick(state)

  @impl true
  def handle_info(:tick, state), do: tick(state)

  def handle_info(:process_next_tool, state), do: process_next_tool(state)

  # SubAgent's final answer arrives via subscriber send/2 (we set ourselves as the
  # subscriber when spawning the sub).
  def handle_info({:agent, :final, content, sub_run_id}, %{pending_delegate: %{sub_run_id: sub_run_id, tc_id: tc_id}} = state) do
    state = append_tool_result(state, tc_id, {:ok, %{"summary" => content, "sub_run_id" => sub_run_id}}, "delegate")
    state = %{state | pending_delegate: nil}
    send(self(), :process_next_tool)
    {:noreply, state}
  end

  def handle_info({:agent, :failed, reason, sub_run_id}, %{pending_delegate: %{sub_run_id: sub_run_id, tc_id: tc_id}} = state) do
    state = append_tool_result(state, tc_id, {:error, "sub-agent failed: #{format_reason(reason)}"}, "delegate")
    state = %{state | pending_delegate: nil}
    send(self(), :process_next_tool)
    {:noreply, state}
  end

  # Ignore other sub-agent events (statuses, intermediate steps).
  def handle_info({:agent, _kind, _payload}, state), do: {:noreply, state}
  def handle_info({:agent, _kind, _payload, _id}, state), do: {:noreply, state}

  # ----- Decisions (HITL) -----

  @impl true
  def handle_cast({:decision, approval_id, kind, opts}, %{pending_approval: %{approval_id: approval_id, tc: tc}} = state) do
    approval = Traces.get_approval!(approval_id)

    case kind do
      :approve ->
        Traces.update_approval!(approval, %{
          status: "approved",
          decided_at: now(),
          decided_by: Keyword.get(opts, :decided_by, "user")
        })

        state = clear_pending_approval(state)
        state = execute_tool_and_record(state, tc, tc.arguments)
        send(self(), :process_next_tool)
        {:noreply, state}

      :revise ->
        new_input = Keyword.fetch!(opts, :input)

        Traces.update_approval!(approval, %{
          status: "revised",
          decided_at: now(),
          revised_input: new_input,
          decided_by: Keyword.get(opts, :decided_by, "user")
        })

        state = clear_pending_approval(state)
        state = execute_tool_and_record(state, %{tc | arguments: new_input}, new_input)
        send(self(), :process_next_tool)
        {:noreply, state}

      :deny ->
        reason = Keyword.get(opts, :reason, "denied by user")

        Traces.update_approval!(approval, %{
          status: "denied",
          decided_at: now(),
          decided_by: Keyword.get(opts, :decided_by, "user"),
          notes: reason
        })

        state = clear_pending_approval(state)
        state = append_tool_result(state, tc.id, {:error, "tool call denied: #{reason}"}, tc.name)
        send(self(), :process_next_tool)
        {:noreply, state}
    end
  end

  # Stale or mismatched decision — ignore.
  def handle_cast({:decision, _, _, _}, state), do: {:noreply, state}

  # ----- Steering (mid-execution user guidance) -----

  def handle_cast({:steer, guidance}, state) do
    # Drop any queued tool calls + any pending approval (the user overrides).
    state =
      state
      |> Map.put(:pending_tool_calls, [])
      |> Map.put(:pending_approval, nil)
      |> Map.put(:pending_delegate, nil)

    # Persist the guidance as a step and inject it into the conversation as
    # a user turn — the next planner call will see it.
    Traces.add_step!(state.run, :steer, %{"guidance" => guidance}, nil)

    Conversation.append_message(state.conversation, %{
      "role" => "user",
      "content" => "[STEERING] " <> guidance
    })

    Traces.update_run!(state.run, %{status: "running"})

    notify(state, {:agent, :steered, %{guidance: guidance}})
    Phoenix.PubSub.broadcast(@pubsub, @runs_topic, {:runs, :updated, state.run.id})

    send(self(), :tick)
    {:noreply, state}
  end

  # ----- Cancellation -----

  def handle_cast(:cancel, state) do
    cancel(state, :user_cancelled)
  end

  # ----- Tick: drive the planning loop -----

  defp tick(%{pending_violation: {from, to}} = state) do
    fail(state, {:workflow_violation, from, to})
  end

  defp tick(%{iteration: i, max_steps: max} = state) when i >= max do
    fail(state, {:max_steps_exceeded, max})
  end

  defp tick(state) do
    state = maybe_run_reflexion(state)
    state = push_status(state, :planning)

    case do_llm_step(state) do
      {:final, content, state} ->
        finish(state, content)

      {:tools, tool_calls, state} ->
        state = push_status(state, :acting)
        state = %{state | pending_tool_calls: tool_calls, iteration: state.iteration + 1}
        process_next_tool(state)

      {:error, reason, state} ->
        fail(state, reason)
    end
  end

  # ----- LLM step -----

  defp do_llm_step(state) do
    messages = Conversation.for_llm(state.conversation)
    {messages, retrieved_step, state} = inject_retrieved_context(state, messages)
    {messages, state} = inject_tot_plan(state, messages)
    messages = inject_reflexion(state, messages)
    tools = available_tools(state)
    started = System.monotonic_time(:millisecond)

    if retrieved_step do
      notify(state, {:agent, :step, %{kind: :retrieve, idx: retrieved_step.idx, payload: retrieved_step.payload}})
    end

    case Adapter.chat(messages, tools: tools, tool_choice: "auto") do
      {:ok, %Response{} = resp} ->
        latency = System.monotonic_time(:millisecond) - started

        :telemetry.execute(
          [:agent, :llm_call, :stop],
          %{duration_ms: latency},
          %{run_id: state.run.id, finish_reason: resp.finish_reason}
        )

        assistant_msg = response_to_assistant_message(resp)
        :ok = Conversation.append_message(state.conversation, assistant_msg)

        {cost_micro, p_tok, c_tok} = cost_breakdown(resp)

        step =
          Traces.add_step!(
            state.run,
            :llm_call,
            %{
              "content" => resp.content,
              "tool_calls" => resp.tool_calls,
              "finish_reason" => resp.finish_reason,
              "usage" => resp.usage,
              "cost_micro_usd" => cost_micro
            },
            latency,
            %{
              cost_micro_usd: cost_micro,
              model: resp.model,
              prompt_tokens: p_tok,
              completion_tokens: c_tok
            }
          )

        state = bump_cost(state, cost_micro, p_tok, c_tok)

        notify(state, {:agent, :step, %{kind: :llm_call, idx: step.idx, payload: step.payload}})

        cond do
          resp.tool_calls != [] -> {:tools, resp.tool_calls, state}
          is_binary(resp.content) -> {:final, resp.content, state}
          true -> {:error, {:empty_response, resp}, state}
        end

      {:error, reason} ->
        {:error, {:llm_error, reason}, state}
    end
  end

  defp available_tools(%{tools_allow: nil}), do: ToolRegistry.descriptors()

  defp available_tools(%{tools_allow: allow}) when is_list(allow) do
    Enum.filter(ToolRegistry.descriptors(), &(&1["name"] in allow))
  end

  # Extract token counts from the response.usage map and price them via
  # the Pricing module. Returns `{cost_micro_usd_or_nil, prompt_tokens,
  # completion_tokens}`.
  defp cost_breakdown(%Response{model: model, usage: usage}) do
    p =
      get_in(usage || %{}, ["prompt_tokens"]) || 0

    c =
      get_in(usage || %{}, ["completion_tokens"]) || 0

    {Pricing.cost_micro_usd(model, usage || %{}), p, c}
  end

  defp bump_cost(state, nil, p, c), do: bump_tokens_only(state, p, c)

  defp bump_cost(state, cost, p, c) do
    run = Traces.accumulate_cost!(state.run, cost, p, c)
    %{state | run: run}
  end

  defp bump_tokens_only(state, p, c) do
    if (p || 0) + (c || 0) > 0 do
      # No price for the model, but still record token usage.
      run = Traces.accumulate_cost!(state.run, 0, p, c)
      %{state | run: run}
    else
      state
    end
  end

  # Auto-RAG: pull top-k long-term memories for the latest user message,
  # transiently prepend them to the LLM payload (NOT stored in the
  # conversation so they don't accumulate), and record a `retrieve` step
  # in the trace for visibility.
  defp inject_retrieved_context(state, messages) do
    {:ok, ctx} = Context.build(state.conversation, state.card)

    case Context.to_system_message(ctx) do
      nil ->
        {messages, nil, state}

      system_msg ->
        {cost_micro, p_tok, _} = embedding_cost(ctx)

        payload =
          ctx
          |> Context.to_step_payload()
          |> Map.put("cost_micro_usd", cost_micro)
          |> Map.put("embedding_model", ctx.embedding_meta && ctx.embedding_meta.model)

        step =
          Traces.add_step!(state.run, :retrieve, payload, nil, %{
            cost_micro_usd: cost_micro,
            model: ctx.embedding_meta && ctx.embedding_meta.model,
            prompt_tokens: p_tok,
            completion_tokens: 0
          })

        state = bump_cost(state, cost_micro, p_tok, 0)

        {prepend_after_first_system(messages, system_msg), step, state}
    end
  end

  defp embedding_cost(%Context{embedding_meta: nil}), do: {nil, 0, 0}

  defp embedding_cost(%Context{embedding_meta: %{model: model, usage: usage}}) do
    p = get_in(usage || %{}, ["prompt_tokens"]) || get_in(usage || %{}, ["total_tokens"]) || 0
    {Pricing.cost_micro_usd(model, usage || %{"prompt_tokens" => p, "completion_tokens" => 0}), p, 0}
  end

  # Conversation already starts with the card's main system prompt. We slip
  # the retrieved-context message in immediately after it (or at the head
  # if there isn't one) so the order stays:
  #   1) main system  2) retrieved context  3) history…
  defp prepend_after_first_system([%{"role" => "system"} = main | rest], retrieved),
    do: [main, retrieved | rest]

  defp prepend_after_first_system(messages, retrieved),
    do: [retrieved | messages]

  # ----- Planning / Reflection (§4) -----

  # Run Reflexion every N iterations (when enabled in the card). Persist a
  # `reflect` step and stash the critique so the next planner turn sees it.
  defp maybe_run_reflexion(state) do
    cfg = reflexion_config(state.card)

    cond do
      not cfg.enabled -> %{state | reflexion_note: nil}
      state.iteration == 0 -> state
      rem(state.iteration, cfg.every_n) != 0 -> state
      state.reflexion_count >= cfg.max_reflections -> state
      true -> run_reflexion(state)
    end
  end

  defp run_reflexion(state) do
    messages = Conversation.for_llm(state.conversation)
    started = System.monotonic_time(:millisecond)

    case Reflexion.critique(messages) do
      {:ok, text} ->
        latency = System.monotonic_time(:millisecond) - started

        step =
          Traces.add_step!(state.run, :reflect, %{
            "critique" => text,
            "iteration" => state.iteration,
            "reflexion_count" => state.reflexion_count + 1
          }, latency)

        notify(state, {:agent, :step, %{kind: :reflect, idx: step.idx, payload: step.payload}})
        notify(state, {:agent, :reflexion, %{critique: text}})

        %{state | reflexion_note: text, reflexion_count: state.reflexion_count + 1}

      {:error, _reason} ->
        # Reflexion is advisory — failures must not break the run.
        state
    end
  end

  defp reflexion_config(card) do
    base = %{enabled: false, every_n: 2, max_reflections: 5}

    case card && card.reasoning_policy do
      %{"reflexion" => map} when is_map(map) ->
        %{
          enabled: Map.get(map, "enabled", false),
          every_n: max(Map.get(map, "every_n", 2), 1),
          max_reflections: Map.get(map, "max_reflections", 5)
        }

      %{"reflection" => true} ->
        # Back-compat: legacy boolean enables a sensible default.
        %{base | enabled: true}

      _ ->
        base
    end
  end

  # Tree-of-Thoughts: run once per turn when planning_strategy == "tot".
  # Returns possibly updated state (tot_note assigned) and the messages
  # list with the chosen-plan system message slipped in.
  defp inject_tot_plan(state, messages) do
    if tot_enabled?(state.card) do
      case ToT.brainstorm(messages) do
        {:ok, %{candidates: cands, chosen: chosen} = result} ->
          step =
            Traces.add_step!(state.run, :plan, %{
              "strategy" => "tot",
              "candidates" => cands,
              "chosen" => chosen
            }, nil)

          notify(state, {:agent, :step, %{kind: :plan, idx: step.idx, payload: step.payload}})
          notify(state, {:agent, :tot, %{candidates: cands, chosen: chosen}})

          state = %{state | tot_note: result}

          case ToT.to_system_message(result) do
            nil -> {messages, state}
            msg -> {append_planning_system(messages, msg), state}
          end

        {:error, _reason} ->
          # ToT is advisory — degrade silently.
          {messages, state}
      end
    else
      {messages, state}
    end
  end

  defp tot_enabled?(nil), do: false

  defp tot_enabled?(card) do
    case card.reasoning_policy do
      %{"planning_strategy" => "tot"} -> true
      _ -> false
    end
  end

  # Stash the latest critique into the next planner turn.
  defp inject_reflexion(%{reflexion_note: nil}, messages), do: messages

  defp inject_reflexion(%{reflexion_note: note}, messages) do
    case Reflexion.to_system_message(note) do
      nil -> messages
      msg -> append_planning_system(messages, msg)
    end
  end

  # Both reflexion + ToT messages slot in after the retrieved-context block
  # so the main system + retrieval still come first.
  defp append_planning_system(messages, system_msg) do
    {systems, rest} = Enum.split_while(messages, &(&1["role"] == "system"))
    systems ++ [system_msg | rest]
  end

  # ----- Queue processing -----

  defp process_next_tool(%{pending_tool_calls: []} = state) do
    # All tools in this round done — observe, reflect, loop.
    state = push_status(state, :observing)
    state = push_status(state, :reflecting)
    send(self(), :tick)
    {:noreply, state}
  end

  defp process_next_tool(%{pending_tool_calls: [tc | rest]} = state) do
    state = %{state | pending_tool_calls: rest}

    cond do
      not workflow_permits_tool?(state, tc) ->
        # Surface the constraint as a tool error so the LLM can adapt.
        state = reject_tool_for_workflow(state, tc)
        send(self(), :process_next_tool)
        {:noreply, state}

      tc.name == "delegate" ->
        start_delegate(state, tc)

      requires_approval?(tc, state.card) ->
        start_approval(state, tc)

      true ->
        state = execute_tool_and_record(state, tc, tc.arguments)
        send(self(), :process_next_tool)
        {:noreply, state}
    end
  end

  defp workflow_permits_tool?(state, %{name: name}) do
    Workflow.tool_allowed_in?(state.workflow, state.status, name)
  end

  defp reject_tool_for_workflow(state, %{id: tc_id, name: name}) do
    allowed = Map.get(state.workflow.allowed_actions, to_string(state.status), [])

    reason =
      "workflow_violation: tool #{inspect(name)} not allowed in state " <>
        "#{inspect(to_string(state.status))} (allowed: #{inspect(allowed)})"

    Traces.add_step!(state.run, :reflect, %{
      "workflow_warning" => "tool_blocked",
      "state" => to_string(state.status),
      "tool" => name,
      "allowed" => allowed,
      "enforce" => Workflow.enforce?(state.workflow)
    }, nil)

    append_tool_result(state, tc_id, {:error, reason}, name)
  end

  # ----- Normal tool execution -----

  defp execute_tool_and_record(state, tc, args) do
    started = System.monotonic_time(:millisecond)

    :telemetry.execute(
      [:agent, :tool_call, :start],
      %{system_time: System.system_time()},
      %{run_id: state.run.id, tool: tc.name}
    )

    result = ToolRegistry.call_with_policy(tc.name, args)
    latency = System.monotonic_time(:millisecond) - started

    {output_payload, error_text, raw_error} =
      case result do
        {:ok, output} -> {output, nil, nil}
        {:error, reason} -> {nil, format_reason(reason), reason}
      end

    step =
      Traces.add_step!(
        state.run,
        :tool_call,
        %{"name" => tc.name, "input" => args, "output" => output_payload, "error" => error_text},
        latency
      )

    Traces.add_tool_call!(state.run, step, %{
      tool_name: tc.name,
      input: args,
      output: output_payload,
      error: error_text,
      latency_ms: latency
    })

    if raw_error do
      Failures.record(%{
        reason: raw_error,
        run_id: state.run.id,
        step_id: step.id,
        tool_error?: true,
        context: %{"tool" => tc.name, "input" => args}
      })
    end

    :telemetry.execute(
      [:agent, :tool_call, :stop],
      %{duration_ms: latency},
      %{run_id: state.run.id, tool: tc.name, error: not is_nil(error_text)}
    )

    notify(state, {:agent, :tool_call, %{name: tc.name, input: args, output: output_payload, error: error_text, latency_ms: latency}})

    append_tool_result(state, tc.id, result, tc.name)
  end

  defp append_tool_result(state, tc_id, result, _tool_name) do
    msg = %{
      "role" => "tool",
      "tool_call_id" => tc_id,
      "content" => tool_result_payload(result)
    }

    :ok = Conversation.append_message(state.conversation, msg)
    state
  end

  defp tool_result_payload({:ok, output}), do: Jason.encode!(output)
  defp tool_result_payload({:error, reason}), do: Jason.encode!(%{"error" => format_reason(reason)})

  # ----- HITL: risk gating -----

  defp requires_approval?(_tc, nil), do: false

  defp requires_approval?(%{name: name}, card) do
    policy = get_in(card.safety_policy, ["human_approval_required_for"]) || []
    risk = ToolRegistry.risk_level(name) |> Atom.to_string()

    risk in policy or name in policy
  end

  defp start_approval(state, tc) do
    risk = ToolRegistry.risk_level(tc.name) |> Atom.to_string()

    approval =
      Traces.create_approval!(%{
        run_id: state.run.id,
        tool_call_id: tc.id,
        tool_name: tc.name,
        input: tc.arguments,
        risk_level: risk
      })

    Traces.update_run!(state.run, %{status: "awaiting_approval"})

    state = push_status(state, :awaiting_approval)
    notify(state, {:agent, :approval_requested, %{
      approval_id: approval.id,
      tool_name: tc.name,
      input: tc.arguments,
      risk_level: risk
    }})

    Phoenix.PubSub.broadcast(@pubsub, @runs_topic, {:runs, :updated, state.run.id})

    {:noreply, %{state | pending_approval: %{approval_id: approval.id, tc: tc}}}
  end

  defp clear_pending_approval(state) do
    Traces.update_run!(state.run, %{status: "running"})
    %{state | pending_approval: nil}
  end

  # ----- SubAgent: delegate -----

  defp start_delegate(state, %{id: tc_id, arguments: args}) do
    task = Map.get(args, "task", "")
    skill_slug = Map.get(args, "skill")
    max_steps = Map.get(args, "max_steps", 6)
    tools_allow = Map.get(args, "tools_allow")

    skill = skill_slug && Skills.get(skill_slug)
    system_prompt = build_sub_system_prompt(skill, state.card, task)

    {:ok, sub_conv} = Conversation.start_link(system_prompt: system_prompt)

    case __MODULE__.start(
           conversation: sub_conv,
           card: state.card,
           user_input: task,
           subscriber: self(),
           max_steps: max_steps,
           parent_run_id: state.run.id,
           skill_slug: skill && skill.slug,
           tools_allow: tools_allow
         ) do
      {:ok, _sub_pid} ->
        sub_run_id = wait_for_sub_run_id(state)

        notify(state, {:agent, :delegated, %{
          sub_run_id: sub_run_id,
          tool_call_id: tc_id,
          skill: skill && skill.slug,
          task: task
        }})

        Traces.add_step!(state.run, :delegate, %{
          "task" => task,
          "skill" => skill && skill.slug,
          "sub_run_id" => sub_run_id
        }, nil)

        {:noreply, %{state | pending_delegate: %{sub_run_id: sub_run_id, tc_id: tc_id}}}

      {:error, reason} ->
        state = append_tool_result(state, tc_id, {:error, "could not start sub-agent: #{inspect(reason)}"}, "delegate")
        send(self(), :process_next_tool)
        {:noreply, state}
    end
  end

  # The sub-agent sends its `{:agent, :started, sub_run_id}` synchronously
  # via the linked subscriber. Receive it before continuing.
  defp wait_for_sub_run_id(_state) do
    receive do
      {:agent, :started, sub_run_id} -> sub_run_id
    after
      5_000 -> "unknown"
    end
  end

  defp build_sub_system_prompt(nil, _card, task) do
    AgenticAiAgent.Agent.Charter.prepend(
      "You are a focused sub-agent spawned to handle a specific task. " <>
        "Use your tools to complete it, then return a single, well-structured final answer.\n\n" <>
        "Task: #{task}"
    )
  end

  defp build_sub_system_prompt(skill, _card, _task) do
    AgenticAiAgent.Agent.Charter.prepend("""
    You are a focused sub-agent. Follow this skill exactly. Produce a single
    final answer that matches the skill's specified output format.

    --- SKILL: #{skill.name} ---

    #{skill.body}
    """)
  end

  # ----- Termination -----

  defp finish(state, content) do
    latency = DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond)

    Traces.update_run!(state.run, %{
      status: "done",
      final_answer: content,
      finished_at: DateTime.utc_now(),
      latency_ms: latency
    })

    Traces.add_step!(state.run, :final, %{"content" => content}, nil)
    persist_reflexion_async(state)
    judge_async(state, content)

    :telemetry.execute(
      [:agent, :run, :stop],
      %{duration_ms: latency},
      %{run_id: state.run.id, status: "done"}
    )

    notify(state, {:agent, :final, content, state.run.id})
    Phoenix.PubSub.broadcast(@pubsub, @runs_topic, {:runs, :updated, state.run.id})
    {:stop, :normal, state}
  end

  defp cancel(state, reason) do
    latency = DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond)

    Traces.update_run!(state.run, %{
      status: "cancelled",
      errors: %{"reason" => format_reason(reason)},
      finished_at: DateTime.utc_now(),
      latency_ms: latency
    })

    Failures.record(%{
      reason: reason,
      run_id: state.run.id,
      context: %{"iteration" => state.iteration}
    })

    persist_reflexion_async(state)

    :telemetry.execute(
      [:agent, :run, :stop],
      %{duration_ms: latency},
      %{run_id: state.run.id, status: "cancelled"}
    )

    notify(state, {:agent, :cancelled, reason, state.run.id})
    Phoenix.PubSub.broadcast(@pubsub, @runs_topic, {:runs, :updated, state.run.id})
    {:stop, :normal, state}
  end

  defp fail(state, reason) do
    latency = DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond)

    Traces.update_run!(state.run, %{
      status: "failed",
      errors: %{"reason" => format_reason(reason)},
      finished_at: DateTime.utc_now(),
      latency_ms: latency
    })

    Failures.record(%{
      reason: reason,
      run_id: state.run.id,
      context: %{"iteration" => state.iteration, "max_steps" => state.max_steps}
    })

    persist_reflexion_async(state)

    :telemetry.execute(
      [:agent, :run, :stop],
      %{duration_ms: latency},
      %{run_id: state.run.id, status: "failed"}
    )

    notify(state, {:agent, :failed, reason, state.run.id})
    Phoenix.PubSub.broadcast(@pubsub, @runs_topic, {:runs, :updated, state.run.id})
    {:stop, :normal, state}
  end

  # Spawn a Task to run the LLM-as-judge pass on the final answer. If the
  # judge's score is below the card's flag_threshold, a `golden_candidate`
  # is auto-created so /feedback surfaces it for HITL curation. Non-
  # blocking: the user sees the answer immediately; the judge runs in the
  # background and is silent on failure.
  defp judge_async(state, content) do
    run = state.run |> Map.put(:final_answer, content)
    card = state.card

    _ =
      Task.Supervisor.start_child(
        AgenticAiAgent.Tools.TaskSupervisor,
        fn -> Judge.judge_run(run, card) end
      )

    :ok
  end

  # Spawn a Task to write the in-run critique to long-term Memory so future
  # runs can semantically retrieve the lesson. Non-blocking: the run
  # terminates immediately, the embedding call happens out-of-band.
  defp persist_reflexion_async(state) do
    note = state.reflexion_note

    if is_binary(note) and note != "" do
      run = state.run
      card = state.card

      _ =
        Task.Supervisor.start_child(
          AgenticAiAgent.Tools.TaskSupervisor,
          fn -> Reflexion.persist_run_critique(run, card, note) end
        )
    end

    :ok
  end

  # ----- Helpers -----

  # Transition the state. On invalid transition:
  #   - record a warning step + emit :workflow_warning,
  #   - if the graph is enforce: true, set `state.pending_violation` so the
  #     next `tick/1` aborts with `{:workflow_violation, from, to}`.
  defp push_status(state, status) do
    case Workflow.validate(state.workflow, state.status, status) do
      :ok ->
        state = persist_workflow_state(state, status)
        notify(state, {:agent, :status, status})
        %{state | status: status}

      {:error, {:invalid_transition, from, to}} ->
        Traces.add_step!(state.run, :reflect, %{
          "workflow_warning" => "invalid_transition",
          "from" => from,
          "to" => to,
          "enforce" => Workflow.enforce?(state.workflow)
        }, nil)

        state = persist_workflow_state(state, status)
        notify(state, {:agent, :status, status})
        notify(state, {:agent, :workflow_warning, %{from: from, to: to}})

        state = %{state | status: status}

        if Workflow.enforce?(state.workflow) do
          Map.put(state, :pending_violation, {from, to})
        else
          state
        end
    end
  end

  # Persist the workflow state on the Run so the UI / replays can show it.
  # Only writes when it actually changes — saves a round-trip per tick.
  defp persist_workflow_state(state, new_status) do
    new_str = to_string(new_status)

    if state.run.workflow_state == new_str do
      state
    else
      run = Traces.update_run!(state.run, %{workflow_state: new_str})
      %{state | run: run}
    end
  end

  defp notify(state, msg) do
    send(state.subscriber, msg)
    Phoenix.PubSub.broadcast(@pubsub, topic(state.run.id), msg)
  end

  defp broadcast_started(run, card, subscriber) do
    started_msg = {:agent, :started, run.id}
    send(subscriber, started_msg)
    Phoenix.PubSub.broadcast(@pubsub, topic(run.id), started_msg)

    Phoenix.PubSub.broadcast(
      @pubsub,
      @runs_topic,
      {:runs, :created,
       %{
         id: run.id,
         status: run.status,
         user_input: run.user_input,
         card_slug: card && card.slug,
         parent_run_id: run.parent_run_id,
         started_at: run.started_at
       }}
    )
  end

  defp response_to_assistant_message(%Response{content: content, tool_calls: []}),
    do: %{"role" => "assistant", "content" => content}

  defp response_to_assistant_message(%Response{content: content, tool_calls: tool_calls}) do
    %{
      "role" => "assistant",
      "content" => content,
      "tool_calls" => Enum.map(tool_calls, &tool_call_to_openai/1)
    }
  end

  defp tool_call_to_openai(%{id: id, name: name, arguments: args}) do
    %{
      "id" => id,
      "type" => "function",
      "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
    }
  end

  defp max_steps_from_card(nil), do: nil

  defp max_steps_from_card(card) do
    case card.reasoning_policy do
      %{"max_steps" => n} when is_integer(n) -> n
      _ -> nil
    end
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
