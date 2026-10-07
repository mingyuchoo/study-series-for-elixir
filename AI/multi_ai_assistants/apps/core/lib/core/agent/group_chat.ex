defmodule Core.Agent.GroupChat do
  @moduledoc """
  모더레이터(Supervisor) 주도 라운드제 그룹 채팅 오케스트레이터.

  사용자 요청에 대해 여러 워커가 순차로 발언하는 토론 형태로 응답을 만듭니다.
  매 라운드마다 모더레이터 LLM이 다음 발언자를 지명하거나 토론을 종료(최종 답변 산출)합니다.

  발화 한 번 = `Message` 한 행:

    - 모더레이터의 발언자 지명 → `role: :assistant`, `agent_id: supervisor`,
      `visibility: :debate_turn`, `content`은 "🎯 X에게 발언권 부여" 류 메타 메시지
    - 워커 발언 → `role: :assistant`, `agent_id: worker`, `visibility: :debate_turn`, 워커가 산출한 내용
    - 최종 답변 → `role: :assistant`, `agent_id: supervisor`, `visibility: :final`,
      모더레이터가 합성한 최종 답변

  `:debate_turn` 가시성은 다음 턴 LLM 컨텍스트에 포함되지 않아 노이즈가 다음 대화로 새지 않습니다.
  """

  require Logger

  alias Core.Agent.{Coordinator, MemoryManager, RunStore, TaskRouter, Telemetry}
  alias Core.Contexts.VectorRags
  alias Core.LLM.AzureOpenAI
  alias Core.Repo
  alias Core.Schema.Message

  @default_max_rounds 6
  # 모더레이터 프롬프트에 포함할 워커 발언 미리보기 길이
  @transcript_excerpt_chars 800

  @type worker_entry :: {Core.Schema.Agent.t(), pid()}

  @type opts :: %{
          required(:supervisor) => Core.Schema.Agent.t(),
          required(:workers) => [worker_entry()],
          required(:conversation_id) => String.t(),
          required(:user_id) => String.t(),
          required(:user_request) => String.t(),
          optional(:liveview_pid) => pid() | nil,
          optional(:max_rounds) => pos_integer()
        }

  @doc """
  그룹 채팅을 1회 실행하고 최종 답변을 반환합니다.

  스트리밍 이벤트는 `liveview_pid`가 주어진 경우에만 전송됩니다.
  """
  @spec run(opts()) :: {:ok, String.t()} | {:error, term()}
  def run(%{} = opts) do
    with {:ok, run} <- RunStore.create(opts.conversation_id, opts.user_id, opts.user_request) do
      opts |> init_state() |> Map.put(:run_id, run.id) |> execute_state()
    end
  end

  def resume(%{} = opts, run_id) do
    case RunStore.get_owned(opts.user_id, run_id) do
      %{status: :running, conversation_id: conversation_id} = run
      when conversation_id == opts.conversation_id ->
        state =
          opts
          |> Map.put(:user_request, run.user_request)
          |> init_state()
          |> Map.merge(%{
            run_id: run.id,
            round: run.round,
            transcript: restore_transcript(run.transcript)
          })

        execute_state(state)

      _ ->
        {:error, :run_not_resumable}
    end
  end

  defp execute_state(state) do
    previous = Process.get(:agent_run_id)
    Process.put(:agent_run_id, state.run_id)

    try do
      Telemetry.measure(
        :run,
        %{run_id: state.run_id, conversation_id: state.conversation_id},
        fn ->
          do_execute_state(state)
        end
      )
    after
      if previous == nil,
        do: Process.delete(:agent_run_id),
        else: Process.put(:agent_run_id, previous)
    end
  end

  defp do_execute_state(state) do
    existing_final = Repo.get_by(Message, agent_run_id: state.run_id)

    notify(
      state,
      {:debate_started, state.conversation_id,
       %{user_request: state.user_request, max_rounds: state.max_rounds, run_id: state.run_id}}
    )

    result = if existing_final, do: {:ok, existing_final.content, state}, else: loop(state)

    case result do
      {:ok, final_answer, _state} ->
        RunStore.finish(state.run_id, final_answer)

        Logger.info(
          "GroupChat finished: conversation=#{state.conversation_id}, rounds=#{state.round}"
        )

        notify(state, {:debate_finished, state.conversation_id, final_answer})
        {:ok, final_answer}

      {:error, reason} = error ->
        RunStore.fail(state.run_id, reason)
        Logger.error("GroupChat failed: #{inspect(reason)}")
        notify(state, {:debate_finished, state.conversation_id, nil})
        error
    end
  end

  ## 내부 상태/루프

  defp init_state(opts) do
    %{
      supervisor: Map.fetch!(opts, :supervisor),
      workers: Map.fetch!(opts, :workers),
      conversation_id: Map.fetch!(opts, :conversation_id),
      user_id: Map.fetch!(opts, :user_id),
      user_request: Map.fetch!(opts, :user_request),
      liveview_pid: Map.get(opts, :liveview_pid),
      max_rounds: Map.get(opts, :max_rounds, @default_max_rounds),
      round: 0,
      transcript: []
    }
  end

  defp loop(state) do
    cond do
      RunStore.cancelled?(state.run_id) ->
        {:error, :cancelled}

      state.round >= state.max_rounds ->
        # 강제 종료: 모더레이터에게 final만 산출하도록 지시
        force_finalize(state)

      true ->
        case run_round(state) do
          {:final, final_answer, state} -> {:ok, final_answer, state}
          {:ok, final_answer, state} -> {:ok, final_answer, state}
          {:continue, state} -> loop(state)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp run_round(state) do
    state = %{state | round: state.round + 1}
    notify(state, {:agent_status, state.conversation_id, state.supervisor.name, :running})

    unless Enum.empty?(state.transcript) do
      notify(state, {:stream_postprocess, state.conversation_id})
    end

    case select_first_round_worker(state) do
      {:ok, worker_name} ->
        run_speaker_decision(state, worker_name, state.user_request, "규칙 기반 라우팅")

      :moderator ->
        run_moderator_round(state)
    end
  end

  defp select_first_round_worker(%{round: 1} = state) do
    workers = Enum.map(state.workers, fn {agent, _pid} -> agent end)

    case TaskRouter.select_worker_with_score(state.user_request, workers) do
      {:ok, worker, score} when score >= 35 -> {:ok, worker.name}
      _ -> :moderator
    end
  end

  defp select_first_round_worker(_state), do: :moderator

  defp run_moderator_round(state) do
    case call_moderator(state, force_final: false) do
      {:ok, %{decision: "final", final_answer: answer, reasoning: reasoning}}
      when is_binary(answer) and answer != "" ->
        finalize(state, answer, reasoning)

      {:ok,
       %{decision: "speak", next_speaker: name, instruction: instruction, reasoning: reasoning}} ->
        run_speaker_decision(state, name, instruction, reasoning)

      {:ok, %{decision: "parallel", assignments: assignments, reasoning: reasoning}} ->
        run_parallel_decision(state, assignments, reasoning)

      {:ok, decision} ->
        Logger.warning("Moderator returned malformed decision: #{inspect(decision)}; finalizing")
        force_finalize(state)

      {:error, reason} ->
        Logger.warning("Moderator LLM failed: #{inspect(reason)}; finalizing")
        force_finalize(state)
    end
  end

  defp run_speaker_decision(state, name, instruction, reasoning) do
    case find_worker(state, name) do
      nil ->
        Logger.warning("Moderator picked unknown worker: #{inspect(name)}; finalizing")
        force_finalize(state)

      {worker_agent, worker_pid} ->
        state = announce_moderator_pick(state, worker_agent, instruction, reasoning)

        handle_worker_turn(
          run_worker_turn(state, worker_agent, worker_pid, instruction),
          worker_agent
        )
    end
  end

  defp run_parallel_decision(state, assignments, reasoning) when is_list(assignments) do
    assignments = Enum.take(assignments, 3)

    workers =
      Enum.map(assignments, fn assignment ->
        name = assignment["worker"]
        instruction = assignment["instruction"]
        {find_worker(state, name), instruction}
      end)

    valid? =
      length(workers) >= 2 and
        Enum.all?(workers, fn {worker, instruction} ->
          match?({_, _}, worker) and is_binary(instruction) and instruction != ""
        end) and
        length(Enum.uniq_by(workers, fn {{agent, _}, _} -> agent.id end)) == length(workers)

    if valid? do
      announced_state =
        Enum.reduce(workers, state, fn {{agent, _pid}, instruction}, acc ->
          announce_moderator_pick(acc, agent, instruction, reasoning)
        end)

      results =
        Task.async_stream(
          workers,
          fn {{agent, pid}, instruction} ->
            {agent, run_worker_turn(announced_state, agent, pid, instruction)}
          end,
          ordered: true,
          max_concurrency: 3,
          timeout: 150_000,
          on_timeout: :kill_task
        )

      next_state =
        Enum.reduce(results, announced_state, fn
          {:ok, {_agent, {:ok, _output, worker_state}}}, acc ->
            append_transcript(acc, List.last(worker_state.transcript))

          {:ok, {agent, {:error, reason, _}}}, acc ->
            append_transcript(acc, %{
              kind: :worker_error,
              round: acc.round,
              speaker: agent.name,
              display_name: agent.display_name || agent.name,
              content: inspect(reason)
            })

          {:exit, reason}, acc ->
            append_transcript(acc, %{
              kind: :worker_error,
              round: acc.round,
              content: inspect(reason)
            })
        end)

      RunStore.checkpoint(next_state.run_id, next_state.round, next_state.transcript)
      {:continue, next_state}
    else
      force_finalize(state)
    end
  end

  defp run_parallel_decision(state, _assignments, _reasoning), do: force_finalize(state)

  defp handle_worker_turn({:ok, _output, state}, _worker_agent) do
    RunStore.checkpoint(state.run_id, state.round, state.transcript)
    {:continue, state}
  end

  defp handle_worker_turn({:error, reason, state}, worker_agent) do
    # 워커가 실패해도 토론을 강제 종료해 부분 답변이라도 반환
    Logger.warning("Worker #{worker_agent.name} failed: #{inspect(reason)}; finalizing")

    state =
      append_transcript(state, %{
        kind: :worker_error,
        round: state.round,
        speaker: worker_agent.name,
        display_name: worker_agent.display_name || worker_agent.name,
        content: "워커 실행 오류: #{inspect(reason)}"
      })

    force_finalize(state)
  end

  defp finalize(state, answer, reasoning) do
    if RunStore.cancelled?(state.run_id) do
      {:error, :cancelled}
    else
      {:ok, message} = persist_final_message(state, answer)
      notify(state, {:debate_message_inserted, state.conversation_id, message})

      state =
        append_transcript(state, %{
          kind: :final,
          round: state.round,
          speaker: state.supervisor.name,
          display_name: state.supervisor.display_name || "Moderator",
          content: answer,
          reasoning: reasoning
        })

      {:final, answer, state}
    end
  end

  defp force_finalize(state) do
    result =
      case call_moderator(state, force_final: true) do
        {:ok, %{decision: "final", final_answer: answer, reasoning: reasoning}}
        when is_binary(answer) and answer != "" ->
          finalize(state, answer, reasoning)

        _ ->
          # 모더레이터도 실패 → transcript의 마지막 워커 발언을 최종 답변으로 사용
          fallback = fallback_final_answer(state)
          finalize(state, fallback, "fallback: 모더레이터 응답 실패")
      end

    case result do
      {:final, answer, state} -> {:ok, answer, state}
      error -> error
    end
  end

  defp fallback_final_answer(state) do
    state.transcript
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{kind: :worker, content: c} when is_binary(c) and c != "" -> c
      _ -> nil
    end)
    |> case do
      nil -> "죄송합니다. 적절한 답변을 만들지 못했습니다."
      content -> content
    end
  end

  defp append_transcript(state, entry) do
    %{
      state
      | transcript: List.insert_at(state.transcript, -1, Map.put(entry, :round, state.round))
    }
  end

  ## 모더레이터 호출

  defp call_moderator(state, opts) do
    force_final? = Keyword.get(opts, :force_final, false)

    messages = [
      %{role: "system", content: moderator_system_prompt(state, force_final?)},
      %{role: "user", content: moderator_user_payload(state, force_final?)}
    ]

    # `model:` 옵션은 일부러 생략합니다. AzureOpenAI 클라이언트는 옵션이 없으면
    # 애플리케이션 설정의 AZURE_OPENAI_DEPLOYMENT 값을 deployment 이름으로 사용합니다.
    # supervisor.model(예: "gpt-5-mini")을 그대로 넘기면 동일한 이름의
    # Azure deployment가 없는 환경에서 404 DeploymentNotFound가 발생합니다.
    # 워커도 ReactEngine을 통해 동일한 폴백 경로를 사용하므로 여기도 일관되게 맞춥니다.
    try do
      case AzureOpenAI.chat_completion(messages,
             temperature: state.supervisor.temperature || 1.0,
             max_completion_tokens: 1200
           ) do
        {:ok, %{content: content}} when is_binary(content) ->
          parse_moderator_output(content)

        {:ok, other} ->
          {:error, {:invalid_moderator_response, other}}

        {:error, _} = err ->
          err
      end
    rescue
      exception -> {:error, {exception.__struct__, Exception.message(exception)}}
    end
  end

  defp moderator_system_prompt(state, force_final?) do
    user_profile_block =
      case MemoryManager.get_user_profile(state.user_id) do
        {:ok, profile} ->
          user_name = Map.get(profile, "user_name") || Map.get(profile, :user_name) || "?"
          city = Map.get(profile, "city") || Map.get(profile, :city) || "?"
          "[사용자: #{user_name}, 위치: #{city}]\n"

        _ ->
          ""
      end

    forced_clause =
      if force_final? do
        """

        IMPORTANT: This is a FORCED FINALIZATION call. You MUST return decision="final"
        with a complete final_answer that synthesizes whatever has been said so far.
        Do NOT pick a new speaker.
        """
      else
        ""
      end

    """
    #{user_profile_block}#{state.supervisor.system_prompt}

    You are the GROUP CHAT MODERATOR. Each round you decide ONE of:
      A) "speak" — pick exactly one worker to take the next turn, with a concrete instruction.
      B) "final" — declare the debate finished and produce the synthesized final answer.
      C) "parallel" — assign 2 or 3 independent subtasks to distinct workers.

    Return ONLY valid JSON. No markdown fences, no commentary.

    Schema:
    {
      "decision": "speak" | "final" | "parallel",
      "next_speaker": "<worker_name>",       // required when decision = "speak"
      "instruction": "<actionable task>",    // required when decision = "speak"
      "assignments": [{"worker": "<worker_name>", "instruction": "<task>"}], // parallel only
      "reasoning": "<one short sentence>",   // always required
      "final_answer": "<markdown answer>"    // required when decision = "final"
    }

    Rules:
    - Use only worker names from the provided list.
    - Use parallel only when subtasks are independent and need no result from each other.
    - Trivial questions: finalize early (round 1 or 2 is fine).
    - Avoid picking the same worker more than 2 rounds in a row.
    - For real-time data (prices, news, weather, URLs), pick `research_worker` first.
    - If the request may benefit from AVAILABLE KNOWLEDGE, pick a worker that has
      `search_vector_rag` and explicitly instruct it to search the relevant knowledge first.
    - `knowledge_worker` has NO web access; never ask it to fetch external data.
    - `restructure_worker` restructures existing content into a requested format;
      only call it when there is substantive content to restructure or the user
      explicitly requested a specific output structure.
    - If the user asked a simple greeting/social message, you may finalize round 1
      with a short, warm answer that uses the user's profile.
    - The final_answer is what the user sees — write it in Korean unless the user
      explicitly used another language. Use Markdown formatting.
    #{forced_clause}
    """
  end

  defp moderator_user_payload(state, _force_final?) do
    workers_json =
      state.workers
      |> Enum.map(fn {agent, _pid} ->
        %{
          name: agent.name,
          display_name: agent.display_name,
          description: agent.description,
          enabled_tools: agent.enabled_tools || []
        }
      end)
      |> Jason.encode!()

    transcript_block = format_transcript_for_moderator(state.transcript)
    knowledge_block = format_available_knowledge(state.user_id)

    """
    USER REQUEST:
    \"\"\"
    #{state.user_request}
    \"\"\"

    AVAILABLE WORKERS (JSON):
    #{workers_json}

    AVAILABLE KNOWLEDGE:
    #{knowledge_block}

    ROUND #{state.round} of #{state.max_rounds}

    DEBATE TRANSCRIPT SO FAR:
    #{transcript_block}
    """
  end

  defp format_transcript_for_moderator([]), do: "(아직 발언 없음 — 토론 시작)"

  defp format_transcript_for_moderator(transcript) do
    Enum.map_join(transcript, "\n\n", fn entry ->
      content = String.slice(entry.content || "", 0, @transcript_excerpt_chars)

      tag =
        case entry.kind do
          :moderator_pick -> "[모더레이터]"
          :worker -> "[#{entry.display_name}]"
          :worker_error -> "[#{entry.display_name} ERROR]"
          :final -> "[최종]"
          _ -> "[?]"
        end

      "라운드 #{entry.round} #{tag}: #{content}"
    end)
  end

  defp parse_moderator_output(content) do
    json_text =
      content
      |> String.trim()
      |> strip_code_fences()

    with {:ok, decoded} <- Jason.decode(json_text) do
      decision = Map.get(decoded, "decision")

      result = %{
        decision: decision,
        next_speaker: Map.get(decoded, "next_speaker"),
        instruction: Map.get(decoded, "instruction"),
        assignments: Map.get(decoded, "assignments"),
        reasoning: Map.get(decoded, "reasoning") || "",
        final_answer: Map.get(decoded, "final_answer")
      }

      {:ok, result}
    end
  end

  defp strip_code_fences(text) do
    text
    |> String.replace(~r/^```(?:json)?\n/, "")
    |> String.replace(~r/\n```\s*$/, "")
  end

  ## 워커 턴 실행

  defp announce_moderator_pick(state, worker_agent, instruction, reasoning) do
    body = """
    🎯 **#{worker_agent.display_name || worker_agent.name}**에게 발언권을 드립니다.

    > #{reasoning}

    **요청 내용**: #{instruction}
    """

    {:ok, message} =
      persist_message(state, %{
        role: :assistant,
        content: body,
        agent_id: state.supervisor.id,
        visibility: :debate_turn
      })

    notify(state, {:debate_message_inserted, state.conversation_id, message})

    %{
      state
      | transcript:
          state.transcript ++
            [
              %{
                kind: :moderator_pick,
                round: state.round,
                speaker: state.supervisor.name,
                display_name: state.supervisor.display_name || "Moderator",
                content: "→ #{worker_agent.name}: #{instruction}"
              }
            ]
    }
  end

  defp run_worker_turn(state, worker_agent, worker_pid, instruction) do
    notify(state, {:agent_status, state.conversation_id, worker_agent.name, :running})

    task_attrs = %{
      conversation_id: state.conversation_id,
      user_id: state.user_id,
      run_id: state.run_id,
      supervisor_id: state.supervisor.id,
      user_request: build_worker_request(state, instruction),
      context:
        "Round #{state.round}/#{state.max_rounds} of group chat. Stay focused on the moderator's instruction."
    }

    stream_callback = build_stream_callback(state, worker_agent)

    case Coordinator.send_task_stream(
           state.supervisor.id,
           worker_agent.id,
           worker_pid,
           task_attrs,
           stream_callback
         ) do
      {:ok, output} ->
        {:ok, message} =
          persist_message(state, %{
            role: :assistant,
            content: output,
            agent_id: worker_agent.id,
            visibility: :debate_turn
          })

        notify(state, {:debate_message_inserted, state.conversation_id, message})
        notify(state, {:agent_status, state.conversation_id, worker_agent.name, :idle})

        new_state =
          append_transcript(state, %{
            kind: :worker,
            round: state.round,
            speaker: worker_agent.name,
            display_name: worker_agent.display_name || worker_agent.name,
            content: output
          })

        {:ok, output, new_state}

      {:error, reason} ->
        notify(state, {:agent_status, state.conversation_id, worker_agent.name, :error})
        {:error, reason, state}
    end
  end

  defp build_worker_request(state, instruction) do
    transcript_text = format_transcript_for_worker(state.transcript)

    """
    [그룹 채팅 라운드 #{state.round}/#{state.max_rounds}]

    원래 사용자 요청:
    #{state.user_request}

    지금까지 발언 요약:
    #{transcript_text}

    이번 라운드에 당신이 할 일:
    #{instruction}

    당신의 역할 범위 안에서만 답하고, 다른 워커가 더 잘하는 일은 권유만 하세요.
    """
  end

  defp format_transcript_for_worker([]), do: "(아직 발언 없음)"

  defp format_transcript_for_worker(transcript) do
    transcript
    |> Enum.filter(&(&1.kind == :worker))
    |> case do
      [] ->
        "(워커 발언 아직 없음)"

      entries ->
        Enum.map_join(entries, "\n", fn entry ->
          excerpt = String.slice(entry.content || "", 0, @transcript_excerpt_chars)
          "- [#{entry.display_name}] #{excerpt}"
        end)
    end
  end

  defp format_available_knowledge(user_id) do
    case VectorRags.list_active_vector_rags(user_id) do
      [] ->
        "(사용 가능한 Vector RAG 지식 없음)"

      vector_rags ->
        Enum.map_join(vector_rags, "\n", fn rag ->
          "- #{rag.name} (#{rag.chunk_count} chunks)#{rag_description(rag)}"
        end)
    end
  end

  defp rag_description(%{description: description})
       when is_binary(description) and description != "" do
    " - #{description}"
  end

  defp rag_description(_rag), do: ""

  defp build_stream_callback(state, worker_agent) do
    fn
      {:chunk, text} ->
        notify(state, {:stream_chunk, state.conversation_id, text})

      {:tool_execution, tool_calls} ->
        tool_names = Enum.map(tool_calls, fn tc -> tc["function"]["name"] end)
        notify(state, {:stream_tool_start, state.conversation_id, tool_names})

      {:tool_completed, tool_calls, failed_tool_names} ->
        tool_names = Enum.map(tool_calls, fn tc -> tc["function"]["name"] end)
        notify(state, {:stream_tool_end, state.conversation_id, tool_names, failed_tool_names})

      {:tool_completed, tool_calls} ->
        tool_names = Enum.map(tool_calls, fn tc -> tc["function"]["name"] end)
        notify(state, {:stream_tool_end, state.conversation_id, tool_names, []})

      {:finish, _reason} ->
        notify(state, {:debate_speaker_finishing, state.conversation_id, worker_agent.name})

      _ ->
        :ok
    end
  end

  ## 메시지 영속화

  defp persist_message(state, attrs) do
    base = %{
      conversation_id: state.conversation_id,
      visibility: Map.get(attrs, :visibility, :debate_turn)
    }

    final_attrs = Map.merge(base, attrs)

    %Message{}
    |> Message.changeset(final_attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        {:ok, Repo.preload(message, :agent)}

      {:error, _} = err ->
        err
    end
  end

  defp persist_final_message(state, content) do
    case Repo.get_by(Message, agent_run_id: state.run_id) do
      nil ->
        persist_message(state, %{
          role: :assistant,
          content: content,
          agent_id: state.supervisor.id,
          visibility: :final,
          agent_run_id: state.run_id
        })

      message ->
        {:ok, Repo.preload(message, :agent)}
    end
  end

  defp restore_transcript(%{"entries" => entries}) when is_list(entries),
    do: restore_entries(entries)

  defp restore_transcript(%{entries: entries}) when is_list(entries), do: restore_entries(entries)
  defp restore_transcript(_), do: []

  defp restore_entries(entries) do
    Enum.map(entries, fn entry ->
      keys = [:kind, :round, :speaker, :display_name, :content, :reasoning, :instruction]

      Map.new(keys, fn key ->
        value = Map.get(entry, key) || Map.get(entry, Atom.to_string(key))

        value =
          if key == :kind and is_binary(value), do: String.to_existing_atom(value), else: value

        {key, value}
      end)
    end)
  end

  ## 보조

  defp find_worker(state, name) when is_binary(name) do
    Enum.find(state.workers, fn {agent, _pid} -> agent.name == name end)
  end

  defp find_worker(_state, _name), do: nil

  defp notify(%{liveview_pid: pid}, message) when is_pid(pid) do
    send(pid, message)
    :ok
  end

  defp notify(_state, _message), do: :ok
end
