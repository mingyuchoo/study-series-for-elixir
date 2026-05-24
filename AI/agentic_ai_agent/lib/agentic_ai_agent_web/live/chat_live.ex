defmodule AgenticAiAgentWeb.ChatLive do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.{Conversation, Design, Feedback}
  alias AgenticAiAgent.Agent.{Charter, Runtime}
  alias AgenticAiAgentWeb.AgentProfiles

  @impl true
  def mount(_params, _session, socket) do
    card = Design.get_card_by_slug("default")
    system_prompt = build_system_prompt(card)

    socket =
      socket
      |> assign(:card, card)
      |> assign(:turns, [])
      |> assign(:awaiting, false)
      |> assign(:status, nil)
      |> assign(:run_id, nil)
      |> assign(:error, nil)
      |> assign(:conversation, nil)
      |> assign(:pending_approval, nil)
      |> assign(:show_steering?, false)
      |> assign(:flagged_run_ids, MapSet.new())
      |> assign(:praised_run_ids, MapSet.new())
      |> assign(:agent_avatar_path, AgentProfiles.default_path(card))
      |> assign(:user_avatar_path, user_avatar_path(socket.assigns[:current_user]))
      |> assign(:form, to_form(%{"text" => ""}))

    socket =
      if connected?(socket) do
        {:ok, conv} = Conversation.start_link(system_prompt: system_prompt)
        assign(socket, :conversation, conv)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("send", %{"text" => text}, socket) do
    text = String.trim(text)

    cond do
      text == "" ->
        {:noreply, socket}

      socket.assigns.awaiting ->
        {:noreply, socket}

      socket.assigns.conversation == nil ->
        {:noreply, assign(socket, :error, "conversation not ready yet")}

      true ->
        {:ok, _runtime} =
          Runtime.start(
            conversation: socket.assigns.conversation,
            card: socket.assigns.card,
            user_input: text,
            subscriber: self()
          )

        {:noreply,
         socket
         |> assign(:awaiting, true)
         |> assign(:status, :starting)
         |> assign(:error, nil)
         |> assign(:show_steering?, false)
         |> assign(:turns, refresh_turns(socket.assigns.conversation))
         |> assign(:form, to_form(%{"text" => ""}))}
    end
  end

  def handle_event("reset", _params, socket) do
    if conv = socket.assigns.conversation, do: Conversation.reset(conv)

    {:noreply,
     socket
     |> assign(:turns, [])
     |> assign(:error, nil)
     |> assign(:status, nil)
     |> assign(:run_id, nil)
     |> assign(:awaiting, false)
     |> assign(:pending_approval, nil)
     |> assign(:show_steering?, false)}
  end

  def handle_event("approve", _params, %{assigns: %{pending_approval: pa, run_id: rid}} = socket)
      when not is_nil(pa) do
    :ok = Runtime.approve(rid, pa.approval_id, decided_by: "chat-user")
    {:noreply, assign(socket, :pending_approval, nil)}
  end

  def handle_event(
        "deny",
        %{"reason" => reason},
        %{assigns: %{pending_approval: pa, run_id: rid}} = socket
      )
      when not is_nil(pa) do
    reason = if String.trim(reason) == "", do: "denied by user", else: reason
    :ok = Runtime.deny(rid, pa.approval_id, reason)
    {:noreply, assign(socket, :pending_approval, nil)}
  end

  def handle_event("deny", _params, socket), do: handle_event("deny", %{"reason" => ""}, socket)

  # Mid-execution steering: queue a guidance message that overrides the
  # planner's next move.
  def handle_event("steer", %{"guidance" => text}, %{assigns: %{run_id: rid}} = socket)
      when is_binary(text) and rid != nil do
    case String.trim(text) do
      "" ->
        {:noreply, socket}

      g ->
        :ok = Runtime.steer(rid, g)
        {:noreply, assign(socket, :show_steering?, false)}
    end
  end

  def handle_event("steer", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_steering", _params, socket) do
    {:noreply, update(socket, :show_steering?, &(!&1))}
  end

  def handle_event("cancel_run", _params, %{assigns: %{run_id: rid}} = socket) when rid != nil do
    :ok = Runtime.cancel(rid)
    {:noreply, assign(socket, :show_steering?, false)}
  end

  def handle_event("cancel_run", _params, socket), do: {:noreply, socket}

  # 👎 — flag the current run's answer as wrong. One flag per run.
  def handle_event("flag_bad_answer", _params, %{assigns: %{run_id: rid}} = socket)
      when is_binary(rid) do
    if MapSet.member?(socket.assigns.flagged_run_ids, rid) do
      {:noreply, socket}
    else
      target_slug = socket.assigns.card && socket.assigns.card.slug

      case Feedback.flag(rid, flagged_by: "chat-user", target_card_slug: target_slug) do
        {:ok, _candidate} ->
          {:noreply,
           socket
           |> assign(:flagged_run_ids, MapSet.put(socket.assigns.flagged_run_ids, rid))
           |> put_flash(
             :info,
             gettext("Flagged. Curate it at /feedback to add it to the regression set.")
           )}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, gettext("Could not flag: %{r}", r: inspect(reason)))}
      end
    end
  end

  def handle_event("flag_bad_answer", _params, socket), do: {:noreply, socket}

  # 👍 — mirror of flag_bad_answer for positive feedback. One praise per run.
  def handle_event("praise_good_answer", _params, %{assigns: %{run_id: rid}} = socket)
      when is_binary(rid) do
    if MapSet.member?(socket.assigns.praised_run_ids, rid) do
      {:noreply, socket}
    else
      target_slug = socket.assigns.card && socket.assigns.card.slug

      case Feedback.praise(rid, flagged_by: "chat-user", target_card_slug: target_slug) do
        {:ok, _candidate} ->
          {:noreply,
           socket
           |> assign(:praised_run_ids, MapSet.put(socket.assigns.praised_run_ids, rid))
           |> put_flash(
             :info,
             gettext(
               "Saved as a win. Curate it at /feedback to add it to the wins set the next eval will check."
             )
           )}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, gettext("Could not praise: %{r}", r: inspect(reason)))}
      end
    end
  end

  def handle_event("praise_good_answer", _params, socket), do: {:noreply, socket}

  # ----- Runtime messages -----

  @impl true
  def handle_info({:agent, :started, run_id}, socket),
    do: {:noreply, assign(socket, :run_id, run_id)}

  def handle_info({:agent, :status, status}, socket),
    do: {:noreply, assign(socket, :status, status)}

  def handle_info({:agent, :step, _payload}, socket) do
    {:noreply, assign(socket, :turns, refresh_turns(socket.assigns.conversation))}
  end

  def handle_info({:agent, :tool_call, _info}, socket) do
    {:noreply, assign(socket, :turns, refresh_turns(socket.assigns.conversation))}
  end

  def handle_info({:agent, :approval_requested, info}, socket) do
    {:noreply, assign(socket, :pending_approval, info)}
  end

  def handle_info({:agent, :delegated, _info}, socket) do
    {:noreply, assign(socket, :turns, refresh_turns(socket.assigns.conversation))}
  end

  def handle_info({:agent, :final, _content, _run_id}, socket) do
    {:noreply,
     socket
     |> assign(:awaiting, false)
     |> assign(:status, :done)
     |> assign(:pending_approval, nil)
     |> assign(:show_steering?, false)
     |> assign(:turns, refresh_turns(socket.assigns.conversation))}
  end

  def handle_info({:agent, :failed, reason, _run_id}, socket) do
    {:noreply,
     socket
     |> assign(:awaiting, false)
     |> assign(:status, :failed)
     |> assign(:show_steering?, false)
     |> assign(:turns, refresh_turns(socket.assigns.conversation))
     |> assign(:error, format_error(reason))}
  end

  def handle_info({:agent, :cancelled, _reason, _run_id}, socket) do
    {:noreply,
     socket
     |> assign(:awaiting, false)
     |> assign(:status, :cancelled)
     |> assign(:pending_approval, nil)
     |> assign(:show_steering?, false)
     |> assign(:turns, refresh_turns(socket.assigns.conversation))}
  end

  def handle_info({:agent, :steered, _info}, socket) do
    {:noreply,
     socket
     |> assign(:turns, refresh_turns(socket.assigns.conversation))
     |> assign(:show_steering?, false)
     |> assign(:pending_approval, nil)}
  end

  def handle_info({:agent, :workflow_warning, _info}, socket),
    do: {:noreply, socket}

  def handle_info({:agent, event, _info}, socket) when event in [:reflexion, :tot],
    do: {:noreply, socket}

  # ----- Helpers -----

  defp refresh_turns(nil), do: []
  defp refresh_turns(conv), do: Conversation.turns(conv)

  defp build_system_prompt(nil),
    do: Charter.prepend("You are a helpful assistant. Respond in the user's language.")

  defp build_system_prompt(card) do
    tool_hint =
      case card.tool_policy do
        %{"allow" => allow} when is_list(allow) and allow != [] ->
          "Available tools: " <>
            Enum.join(allow, ", ") <>
            ". Use them only when they help; otherwise answer directly."

        _ ->
          ""
      end

    body =
      [
        "You are the agent described by this card.",
        "Name: #{card.name}",
        card.role && "Role:\n#{card.role}",
        card.goal && "Goal:\n#{card.goal}",
        card.scope && "Scope:\n#{card.scope}",
        tool_hint != "" && tool_hint,
        "Respond in the user's language."
      ]
      |> Enum.reject(&(&1 in [nil, false, ""]))
      |> Enum.join("\n\n")

    Charter.prepend(body)
  end

  defp format_error({:llm_error, {:missing_config, key}}),
    do:
      gettext("Azure OpenAI is not configured (missing %{key}). Set AZURE_OPENAI_* env vars.",
        key: to_string(key)
      )

  defp format_error({:llm_error, {:http_error, status, body}}),
    do:
      gettext("LLM HTTP %{status}: %{body}",
        status: status,
        body: inspect(body) |> String.slice(0, 300)
      )

  defp format_error({:llm_error, {:transport_error, msg}}),
    do: gettext("Network error: %{msg}", msg: inspect(msg))

  defp format_error({:max_steps_exceeded, n}),
    do: gettext("Stopped after %{n} steps without a final answer.", n: n)

  defp format_error({:empty_response, _}),
    do: gettext("Model returned neither text nor a tool call.")

  defp format_error(other), do: inspect(other)

  # ----- Render -----

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_path={@current_path}
      locale={@locale}
      current_user={@current_user}
    >
      <div class="flex h-[calc(100vh-9.5rem)] flex-col">
        <header class="mb-4 flex items-end justify-between">
          <div>
            <p class="eyebrow">{gettext("Conversation")}</p>
            <h1 class="text-[40px] font-medium leading-none tracking-[-0.02em]">
              {gettext("Chat")}
            </h1>
            <p class="text-xs opacity-60">
              {gettext("Card:")}
              <code :if={@card}>{@card.slug}</code><span :if={!@card}>{gettext("(none)")}</span>
              <span :if={@run_id} class="font-mono">
                · {gettext("run")} {String.slice(@run_id, 0, 8)}
              </span>
            </p>
          </div>
          <button
            phx-click="reset"
            type="button"
            class="rounded-full border border-base-content px-5 py-2 text-sm font-medium tracking-[-0.02em] hover:bg-base-200"
          >
            {gettext("Reset")}
          </button>
        </header>

        <div
          id="messages"
          phx-hook=".AutoScroll"
          class="flex-1 space-y-4 overflow-y-auto rounded-[40px] border border-base-content/80 bg-base-100 p-5"
        >
          <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoScroll">
            // Auto-scroll the chat output so the latest message stays
            // visible — but only if the user is already near the bottom.
            // If they've scrolled up to re-read older context, we leave
            // their position alone instead of yanking them down.
            export default {
              mounted() {
                this.scrollToBottom()
              },
              beforeUpdate() {
                const threshold = 120
                const distanceFromBottom =
                  this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight
                this.shouldScroll = distanceFromBottom < threshold
              },
              updated() {
                if (this.shouldScroll) this.scrollToBottom()
              },
              scrollToBottom() {
                this.el.scrollTo({ top: this.el.scrollHeight, behavior: "smooth" })
              }
            }
          </script>
          <div :if={@turns == []} class="text-center text-sm opacity-50">
            {gettext("Ask something to begin.")}
          </div>
          <div :for={msg <- @turns} class={["flex", role_align(msg["role"])]}>
            <.message
              msg={msg}
              agent_avatar_path={@agent_avatar_path}
              user_avatar_path={@user_avatar_path}
            />
          </div>
          <div :if={@awaiting} class="flex justify-start">
            <div class="flex items-start gap-2">
              <.agent_avatar path={@agent_avatar_path} />
              <div class="rounded-full bg-base-200 px-4 py-2 text-sm leading-snug opacity-70">
                {status_label(@status)}
              </div>
            </div>
          </div>
        </div>
        
    <!-- Feedback strip: 👍 great answer / 👎 wrong answer.
             Both buttons coexist so the agent gets symmetric signal
             (positives go to wins.jsonl, negatives to regressions.jsonl). -->
        <div
          :if={@status == :done and not is_nil(@run_id)}
          class="mt-2 flex items-center justify-end gap-2 text-xs"
        >
          <span :if={MapSet.member?(@praised_run_ids, @run_id)} class="opacity-70">
            {gettext("Praised ✓ — see /feedback")}
          </span>
          <button
            :if={
              not MapSet.member?(@praised_run_ids, @run_id) and
                not MapSet.member?(@flagged_run_ids, @run_id)
            }
            type="button"
            phx-click="praise_good_answer"
            title={gettext("Mark this answer as great — it'll go to the wins queue at /feedback.")}
            class="inline-flex items-center gap-1 rounded-full border border-base-content/20 px-3 py-1 hover:bg-base-200"
          >
            <.icon name="hero-hand-thumb-up" class="size-4" /> {gettext("This answer was great")}
          </button>

          <span :if={MapSet.member?(@flagged_run_ids, @run_id)} class="opacity-70">
            {gettext("Flagged ✓ — see /feedback")}
          </span>
          <button
            :if={
              not MapSet.member?(@flagged_run_ids, @run_id) and
                not MapSet.member?(@praised_run_ids, @run_id)
            }
            type="button"
            phx-click="flag_bad_answer"
            title={
              gettext("Mark this answer as wrong — it'll go to the curation queue at /feedback.")
            }
            class="inline-flex items-center gap-1 rounded-full border border-base-content/20 px-3 py-1 hover:bg-base-200"
          >
            <.icon name="hero-hand-thumb-down" class="size-4" /> {gettext("This answer was wrong")}
          </button>
        </div>

        <div :if={@awaiting and not is_nil(@run_id)} class="mt-2 space-y-2">
          <div class="flex items-center justify-end gap-2">
            <button
              type="button"
              phx-click="toggle_steering"
              class="rounded-full border border-base-content/20 px-3 py-1 text-xs hover:bg-base-200"
            >
              {gettext("Steering")}
            </button>
            <button
              type="button"
              phx-click="cancel_run"
              data-confirm={gettext("Cancel this run?")}
              class="rounded-full border border-[#CF4500] px-3 py-1 text-xs text-[#CF4500] hover:bg-red-50 dark:hover:bg-red-950/40"
            >
              {gettext("Cancel run")}
            </button>
          </div>

          <div
            :if={@show_steering?}
            class="rounded-[40px] border border-[#F37338] bg-base-200 p-4"
          >
            <form phx-submit="steer" class="flex gap-2">
              <input
                name="guidance"
                placeholder={gettext("Redirect the agent... (e.g. 'use http_fetch instead')")}
                autocomplete="off"
                class="flex-1 rounded-full border border-base-content/50 bg-base-100 px-4 py-2 text-xs"
              />
              <button
                type="submit"
                class="rounded-full bg-[#141413] px-4 py-2 text-xs text-[#F3F0EE]"
              >
                {gettext("Steer")}
              </button>
            </form>
          </div>
        </div>

        <div
          :if={@pending_approval}
          class="mt-2 rounded-[40px] border-2 border-[#CF4500] bg-red-50 dark:bg-red-950/40 p-4"
        >
          <div class="mb-2 font-semibold text-red-800 dark:text-red-200">
            ⚠ {gettext("Approval required")}
          </div>
          <div class="text-xs">
            <div>{gettext("tool:")} <code class="font-mono">{@pending_approval.tool_name}</code></div>
            <div>
              {gettext("risk:")} <code class="font-mono">{@pending_approval.risk_level}</code>
            </div>
          </div>
          <pre class="mt-2 overflow-x-auto rounded-[20px] bg-base-100 p-3 text-xs">{Jason.encode!(@pending_approval.input, pretty: true)}</pre>
          <form phx-submit="deny" class="mt-2 flex items-center gap-2">
            <input
              name="reason"
              placeholder={gettext("reason (optional)")}
              class="flex-1 rounded-full border px-4 py-2 text-xs"
            />
            <button
              type="button"
              phx-click="approve"
              class="rounded-full bg-[#141413] px-4 py-2 text-xs text-[#F3F0EE]"
            >
              {gettext("Approve")}
            </button>
            <button
              type="submit"
              class="rounded-full bg-[#CF4500] px-4 py-2 text-xs text-white"
            >
              {gettext("Deny")}
            </button>
          </form>
        </div>

        <div
          :if={@error}
          class="mt-2 rounded-[20px] border border-red-400 dark:border-red-600 bg-red-50 dark:bg-red-950/40 p-3 text-xs text-red-700 dark:text-red-200"
        >
          {@error}
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".FocusOnReady">
          export default {
            mounted() {
              this.focusIfReady()
              this.wasDisabled = this.el.disabled
            },
            beforeUpdate() {
              this.wasDisabled = this.el.disabled
            },
            updated() {
              if (this.wasDisabled && !this.el.disabled) this.focusIfReady()
            },
            focusIfReady() {
              if (this.el.disabled) return
              requestAnimationFrame(() => this.el.focus())
            }
          }
        </script>
        <.form for={@form} phx-submit="send" class="mt-4 flex gap-3">
          <input
            id="chat-message-input"
            name="text"
            value={@form[:text].value}
            placeholder={gettext("Type a message...")}
            autocomplete="off"
            phx-hook=".FocusOnReady"
            class="flex-1 rounded-full border border-base-content bg-base-100 px-5 py-3 text-sm"
            disabled={@awaiting}
          />
          <button
            type="submit"
            disabled={@awaiting}
            class="px-7 py-3 text-sm font-medium disabled:opacity-50"
            style="background:#141413;color:#F3F0EE;border-radius:20px;letter-spacing:-0.02em;"
          >
            {gettext("Send")}
          </button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  # ----- Message components -----

  attr :msg, :map, required: true
  attr :agent_avatar_path, :string, default: nil
  attr :user_avatar_path, :string, default: nil

  defp message(%{msg: %{"role" => "user"}} = assigns) do
    assigns = assign(assigns, :content, clean_content(assigns.msg["content"]))

    ~H"""
    <div class="flex max-w-[75%] items-start gap-2">
      <div class="rounded-[32px] border border-base-content/10 bg-white px-4 py-2 text-sm leading-snug text-[#141413]">
        <div class="text-[11px] font-bold uppercase leading-none tracking-[0.04em] opacity-55">
          {gettext("user")}
        </div>
        <div class="whitespace-pre-wrap">{@content}</div>
      </div>
      <.profile_avatar path={@user_avatar_path} />
    </div>
    """
  end

  defp message(%{msg: %{"role" => "assistant", "tool_calls" => calls}} = assigns)
       when is_list(calls) and calls != [] do
    assigns =
      assigns
      |> assign(:calls, calls)
      |> assign(:content, clean_content(assigns.msg["content"]))

    ~H"""
    <div class="flex max-w-[75%] items-start gap-2">
      <.agent_avatar path={@agent_avatar_path} />
      <div class="space-y-1 rounded-[32px] border border-[#F37338]/50 bg-base-200 px-4 py-2 text-sm leading-snug">
        <div class="text-[11px] font-bold uppercase leading-none tracking-[0.04em] opacity-55">
          {gettext("assistant · calling tools")}
        </div>
        <div :if={@content != ""} class="whitespace-pre-wrap">{@content}</div>
        <ul class="space-y-0.5">
          <li :for={c <- @calls} class="font-mono text-xs">
            → {c["function"]["name"]}({trunc_text(c["function"]["arguments"], 140)})
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp message(%{msg: %{"role" => "assistant"}} = assigns) do
    assigns = assign(assigns, :content, clean_content(assigns.msg["content"]))

    ~H"""
    <div class="flex max-w-[75%] items-start gap-2">
      <.agent_avatar path={@agent_avatar_path} />
      <div class="rounded-[32px] bg-base-200 px-4 py-2 text-sm leading-snug">
        <div class="text-[11px] font-bold uppercase leading-none tracking-[0.04em] opacity-55">
          {gettext("assistant")}
        </div>
        <div class="whitespace-pre-wrap">{@content}</div>
      </div>
    </div>
    """
  end

  defp message(%{msg: %{"role" => "tool"}} = assigns) do
    ~H"""
    <div class="max-w-[75%] rounded-[32px] border border-emerald-300 dark:border-emerald-700 bg-emerald-50 dark:bg-emerald-950/40 px-4 py-2 text-sm leading-snug">
      <div class="text-[11px] font-bold uppercase leading-none tracking-[0.04em] opacity-55">
        {gettext("tool result")}
      </div>
      <pre class="overflow-x-auto whitespace-pre-wrap text-xs">{trunc_text(@msg["content"], 600)}</pre>
    </div>
    """
  end

  defp message(%{msg: msg} = assigns) do
    assigns = assign(assigns, :msg, msg)

    ~H"""
    <div class="max-w-[75%] rounded-[32px] bg-base-300 px-4 py-2 text-xs leading-snug opacity-70">
      {inspect(@msg)}
    </div>
    """
  end

  attr :path, :string, required: true

  defp agent_avatar(assigns) do
    ~H"""
    <img
      src={@path}
      alt=""
      class="mt-0.5 h-8 w-8 shrink-0 rounded-full border border-base-300 bg-base-200 object-cover"
    />
    """
  end

  attr :path, :string, required: true

  defp profile_avatar(assigns) do
    ~H"""
    <img
      src={@path}
      alt=""
      class="mt-0.5 h-8 w-8 shrink-0 rounded-full border border-base-300 bg-base-200 object-cover"
    />
    """
  end

  defp role_align("user"), do: "justify-end"
  defp role_align(_), do: "justify-start"

  defp status_label(:starting), do: gettext("starting…")
  defp status_label(:planning), do: gettext("thinking…")
  defp status_label(:acting), do: gettext("calling tools…")
  defp status_label(:observing), do: gettext("reading results…")
  defp status_label(:reflecting), do: gettext("reflecting…")
  defp status_label(:awaiting_approval), do: gettext("waiting for approval…")
  defp status_label(:cancelled), do: gettext("cancelled")
  defp status_label(_), do: "…"

  defp clean_content(nil), do: ""
  defp clean_content(text) when is_binary(text), do: String.trim(text)
  defp clean_content(other), do: inspect(other)

  defp user_avatar_path(%{avatar_path: path}) when is_binary(path) and path != "", do: path
  defp user_avatar_path(_), do: AgentProfiles.default_path(%{})

  defp trunc_text(nil, _n), do: ""

  defp trunc_text(text, n) when is_binary(text) do
    if String.length(text) > n, do: String.slice(text, 0, n) <> "…", else: text
  end

  defp trunc_text(other, n), do: trunc_text(inspect(other), n)
end
