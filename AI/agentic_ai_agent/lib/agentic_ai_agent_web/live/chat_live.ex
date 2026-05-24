defmodule AgenticAiAgentWeb.ChatLive do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.{Conversation, Design, Feedback}
  alias AgenticAiAgent.Agent.{Charter, Runtime}

  @agent_avatar_paths [
    "/images/avatars/avatar-01.png",
    "/images/avatars/avatar-02.png",
    "/images/avatars/avatar-03.png",
    "/images/avatars/avatar-04.png",
    "/images/avatars/avatar-05.png",
    "/images/avatars/avatar-06.png",
    "/images/avatars/avatar-07.png"
  ]

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
      |> assign(:flagged_run_ids, MapSet.new())
      |> assign(:praised_run_ids, MapSet.new())
      |> assign(:agent_avatar_paths, @agent_avatar_paths)
      |> assign(:agent_avatar_path, default_agent_avatar_path(card))
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
     |> assign(:pending_approval, nil)}
  end

  def handle_event("select_agent_avatar", %{"path" => path}, socket) do
    if valid_agent_avatar_path?(path) do
      {:noreply, assign(socket, :agent_avatar_path, path)}
    else
      {:noreply, socket}
    end
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
        {:noreply, socket}
    end
  end

  def handle_event("steer", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_run", _params, %{assigns: %{run_id: rid}} = socket) when rid != nil do
    :ok = Runtime.cancel(rid)
    {:noreply, socket}
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
     |> assign(:turns, refresh_turns(socket.assigns.conversation))}
  end

  def handle_info({:agent, :failed, reason, _run_id}, socket) do
    {:noreply,
     socket
     |> assign(:awaiting, false)
     |> assign(:status, :failed)
     |> assign(:turns, refresh_turns(socket.assigns.conversation))
     |> assign(:error, format_error(reason))}
  end

  def handle_info({:agent, :cancelled, _reason, _run_id}, socket) do
    {:noreply,
     socket
     |> assign(:awaiting, false)
     |> assign(:status, :cancelled)
     |> assign(:pending_approval, nil)
     |> assign(:turns, refresh_turns(socket.assigns.conversation))}
  end

  def handle_info({:agent, :steered, _info}, socket) do
    {:noreply,
     socket
     |> assign(:turns, refresh_turns(socket.assigns.conversation))
     |> assign(:pending_approval, nil)}
  end

  def handle_info({:agent, :workflow_warning, _info}, socket),
    do: {:noreply, socket}

  # ----- Helpers -----

  defp refresh_turns(nil), do: []
  defp refresh_turns(conv), do: Conversation.turns(conv)

  defp default_agent_avatar_path(%{metadata: %{"agent_avatar_path" => path}})
       when is_binary(path) do
    if valid_agent_avatar_path?(path), do: path, else: List.first(@agent_avatar_paths)
  end

  defp default_agent_avatar_path(_card), do: List.first(@agent_avatar_paths)

  defp valid_agent_avatar_path?(path), do: path in @agent_avatar_paths

  defp avatar_number(path) do
    path
    |> Path.basename(".png")
    |> String.replace("avatar-", "")
  end

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
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="flex h-[calc(100vh-8rem)] flex-col">
        <header class="mb-3 flex items-start justify-between gap-4">
          <div>
            <h1 class="text-2xl font-semibold">{gettext("Chat")}</h1>
            <p class="text-xs opacity-60">
              {gettext("Card:")}
              <code :if={@card}>{@card.slug}</code><span :if={!@card}>{gettext("(none)")}</span>
              <span :if={@run_id} class="font-mono">
                · {gettext("run")} {String.slice(@run_id, 0, 8)}
              </span>
            </p>
          </div>

          <div class="flex flex-wrap items-center justify-end gap-2">
            <div
              id="agent-avatar-picker"
              phx-hook=".AgentAvatarPicker"
              data-current={@agent_avatar_path}
              class="flex items-center gap-1"
            >
              <script :type={Phoenix.LiveView.ColocatedHook} name=".AgentAvatarPicker">
                const key = "agentic_ai_agent.agent_avatar_path"

                export default {
                  mounted() {
                    const stored = window.localStorage.getItem(key)
                    const paths = this.paths()

                    if (stored && paths.includes(stored) && stored !== this.el.dataset.current) {
                      this.pushEvent("select_agent_avatar", { path: stored })
                    }

                    this.el.addEventListener("click", (event) => {
                      const button = event.target.closest("[data-avatar-path]")
                      if (!button) return
                      window.localStorage.setItem(key, button.dataset.avatarPath)
                    })
                  },
                  paths() {
                    return [...this.el.querySelectorAll("[data-avatar-path]")]
                      .map((button) => button.dataset.avatarPath)
                  }
                }
              </script>
              <button
                :for={path <- @agent_avatar_paths}
                type="button"
                phx-click="select_agent_avatar"
                phx-value-path={path}
                data-avatar-path={path}
                title={"Agent profile #{avatar_number(path)}"}
                aria-label={"Agent profile #{avatar_number(path)}"}
                class={[
                  "h-8 w-8 overflow-hidden rounded-full border bg-base-200 p-0 transition hover:scale-105",
                  @agent_avatar_path == path && "border-base-content ring-2 ring-base-content",
                  @agent_avatar_path != path && "border-base-300 opacity-75 hover:opacity-100"
                ]}
              >
                <img src={path} alt="" class="h-full w-full object-cover" />
              </button>
            </div>
            <button
              phx-click="reset"
              type="button"
              class="rounded border px-3 py-1 text-xs hover:bg-base-200"
            >
              {gettext("Reset")}
            </button>
          </div>
        </header>

        <div
          id="messages"
          phx-hook=".AutoScroll"
          class="flex-1 space-y-3 overflow-y-auto rounded border p-3"
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
            <.message msg={msg} agent_avatar_path={@agent_avatar_path} />
          </div>
          <div :if={@awaiting} class="flex justify-start">
            <div class="flex items-start gap-2">
              <.agent_avatar path={@agent_avatar_path} />
              <div class="rounded-lg bg-base-200 px-2.5 py-1 text-sm leading-snug opacity-70">
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
            class="rounded-full border border-base-300 px-3 py-1 hover:bg-base-300/40"
          >
            👍 {gettext("This answer was great")}
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
            class="rounded-full border border-base-300 px-3 py-1 hover:bg-base-300/40"
          >
            👎 {gettext("This answer was wrong")}
          </button>
        </div>

        <div
          :if={@awaiting and not is_nil(@run_id)}
          class="mt-2 rounded-lg border border-amber-300 dark:border-amber-700 bg-amber-50 dark:bg-amber-950/40 p-3"
        >
          <div class="mb-1 flex items-center justify-between">
            <span class="text-xs font-semibold text-amber-800 dark:text-amber-200">
              {gettext("Steering")}
            </span>
            <button
              type="button"
              phx-click="cancel_run"
              data-confirm={gettext("Cancel this run?")}
              class="rounded border border-red-400 dark:border-red-600 px-2 py-0.5 text-[10px] text-red-700 dark:text-red-200 hover:bg-red-100 dark:hover:bg-red-900/40"
            >
              {gettext("Cancel run")}
            </button>
          </div>
          <form phx-submit="steer" class="flex gap-2">
            <input
              name="guidance"
              placeholder={gettext("Redirect the agent... (e.g. 'use http_fetch instead')")}
              autocomplete="off"
              class="flex-1 rounded border px-2 py-1 text-xs"
            />
            <button
              type="submit"
              class="rounded bg-amber-700 dark:bg-amber-600 px-3 py-1 text-xs text-white hover:bg-amber-800"
            >
              {gettext("Steer")}
            </button>
          </form>
        </div>

        <div
          :if={@pending_approval}
          class="mt-2 rounded-lg border-2 border-red-400 dark:border-red-600 bg-red-50 dark:bg-red-950/40 p-3"
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
          <pre class="mt-2 overflow-x-auto rounded bg-base-100 p-2 text-xs">{Jason.encode!(@pending_approval.input, pretty: true)}</pre>
          <form phx-submit="deny" class="mt-2 flex items-center gap-2">
            <input
              name="reason"
              placeholder={gettext("reason (optional)")}
              class="flex-1 rounded border px-2 py-1 text-xs"
            />
            <button
              type="button"
              phx-click="approve"
              class="rounded bg-emerald-600 px-3 py-1 text-xs text-white hover:bg-emerald-700"
            >
              {gettext("Approve")}
            </button>
            <button
              type="submit"
              class="rounded bg-red-600 px-3 py-1 text-xs text-white hover:bg-red-700"
            >
              {gettext("Deny")}
            </button>
          </form>
        </div>

        <div
          :if={@error}
          class="mt-2 rounded border border-red-400 dark:border-red-600 bg-red-50 dark:bg-red-950/40 p-2 text-xs text-red-700 dark:text-red-200"
        >
          {@error}
        </div>

        <.form for={@form} phx-submit="send" class="mt-3 flex gap-2">
          <input
            name="text"
            value={@form[:text].value}
            placeholder={gettext("Type a message...")}
            autocomplete="off"
            class="flex-1 rounded border px-3 py-2 text-sm"
            disabled={@awaiting}
          />
          <button
            type="submit"
            disabled={@awaiting}
            class="px-6 py-2 text-sm font-medium disabled:opacity-50"
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

  defp message(%{msg: %{"role" => "user"}} = assigns) do
    assigns = assign(assigns, :content, clean_content(assigns.msg["content"]))

    ~H"""
    <div class="max-w-[75%] rounded-lg bg-blue-100 dark:bg-blue-900/40 px-2.5 py-1 text-sm leading-snug">
      <div class="font-mono text-[10px] leading-none uppercase opacity-60">{gettext("user")}</div>
      <div class="whitespace-pre-wrap">{@content}</div>
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
      <div class="space-y-0.5 rounded-lg border border-amber-300 dark:border-amber-700 bg-amber-50 dark:bg-amber-950/40 px-2.5 py-1 text-sm leading-snug">
        <div class="font-mono text-[10px] leading-none uppercase opacity-60">
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
      <div class="rounded-lg bg-base-200 px-2.5 py-1 text-sm leading-snug">
        <div class="font-mono text-[10px] leading-none uppercase opacity-60">
          {gettext("assistant")}
        </div>
        <div class="whitespace-pre-wrap">{@content}</div>
      </div>
    </div>
    """
  end

  defp message(%{msg: %{"role" => "tool"}} = assigns) do
    ~H"""
    <div class="max-w-[75%] rounded-lg border border-emerald-300 dark:border-emerald-700 bg-emerald-50 dark:bg-emerald-950/40 px-2.5 py-1 text-sm leading-snug">
      <div class="font-mono text-[10px] leading-none uppercase opacity-60">
        {gettext("tool result")}
      </div>
      <pre class="overflow-x-auto whitespace-pre-wrap text-xs">{trunc_text(@msg["content"], 600)}</pre>
    </div>
    """
  end

  defp message(%{msg: msg} = assigns) do
    assigns = assign(assigns, :msg, msg)

    ~H"""
    <div class="max-w-[75%] rounded-lg bg-base-300 px-2.5 py-1 text-xs leading-snug opacity-70">
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

  defp trunc_text(nil, _n), do: ""

  defp trunc_text(text, n) when is_binary(text) do
    if String.length(text) > n, do: String.slice(text, 0, n) <> "…", else: text
  end

  defp trunc_text(other, n), do: trunc_text(inspect(other), n)
end
