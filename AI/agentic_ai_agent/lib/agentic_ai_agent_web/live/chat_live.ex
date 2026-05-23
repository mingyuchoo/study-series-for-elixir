defmodule AgenticAiAgentWeb.ChatLive do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.{Conversation, Design}
  alias AgenticAiAgent.Agent.Runtime

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

  def handle_event("approve", _params, %{assigns: %{pending_approval: pa, run_id: rid}} = socket)
      when not is_nil(pa) do
    :ok = Runtime.approve(rid, pa.approval_id, decided_by: "chat-user")
    {:noreply, assign(socket, :pending_approval, nil)}
  end

  def handle_event("deny", %{"reason" => reason}, %{assigns: %{pending_approval: pa, run_id: rid}} = socket)
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
      "" -> {:noreply, socket}
      g -> :ok = Runtime.steer(rid, g); {:noreply, socket}
    end
  end

  def handle_event("steer", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_run", _params, %{assigns: %{run_id: rid}} = socket) when rid != nil do
    :ok = Runtime.cancel(rid)
    {:noreply, socket}
  end

  def handle_event("cancel_run", _params, socket), do: {:noreply, socket}

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

  defp build_system_prompt(nil),
    do: "You are a helpful assistant. Respond in the user's language."

  defp build_system_prompt(card) do
    tool_hint =
      case card.tool_policy do
        %{"allow" => allow} when is_list(allow) and allow != [] ->
          "Available tools: " <> Enum.join(allow, ", ") <>
            ". Use them only when they help; otherwise answer directly."

        _ ->
          ""
      end

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
  end

  defp format_error({:llm_error, {:missing_config, key}}),
    do: gettext("Azure OpenAI is not configured (missing %{key}). Set AZURE_OPENAI_* env vars.", key: to_string(key))

  defp format_error({:llm_error, {:http_error, status, body}}),
    do: gettext("LLM HTTP %{status}: %{body}", status: status, body: inspect(body) |> String.slice(0, 300))

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
      <div class="mx-auto flex h-[calc(100vh-8rem)] max-w-3xl flex-col">
        <header class="mb-3 flex items-baseline justify-between">
          <div>
            <h1 class="text-2xl font-semibold">{gettext("Chat")}</h1>
            <p class="text-xs opacity-60">
              {gettext("Card:")} <code :if={@card}>{@card.slug}</code><span :if={!@card}>{gettext("(none)")}</span>
              <span :if={@run_id} class="font-mono">· {gettext("run")} {String.slice(@run_id, 0, 8)}</span>
            </p>
          </div>
          <button
            phx-click="reset"
            type="button"
            class="rounded border px-3 py-1 text-xs hover:bg-base-200"
          >
            {gettext("Reset")}
          </button>
        </header>

        <div id="messages" class="flex-1 space-y-3 overflow-y-auto rounded border p-3">
          <div :if={@turns == []} class="text-center text-sm opacity-50">
            {gettext("Ask something to begin.")}
          </div>
          <div :for={msg <- @turns} class={["flex", role_align(msg["role"])]}>
            <.message msg={msg} />
          </div>
          <div :if={@awaiting} class="flex justify-start">
            <div class="rounded-lg bg-base-200 px-3 py-2 text-sm opacity-70">
              {status_label(@status)}
            </div>
          </div>
        </div>

        <div :if={@awaiting and not is_nil(@run_id)} class="mt-2 rounded-lg border border-amber-300 dark:border-amber-700 bg-amber-50 dark:bg-amber-950/40 p-3">
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
            <button type="submit" class="rounded bg-amber-700 dark:bg-amber-600 px-3 py-1 text-xs text-white hover:bg-amber-800">
              {gettext("Steer")}
            </button>
          </form>
        </div>

        <div :if={@pending_approval} class="mt-2 rounded-lg border-2 border-red-400 dark:border-red-600 bg-red-50 dark:bg-red-950/40 p-3">
          <div class="mb-2 font-semibold text-red-800 dark:text-red-200">
            ⚠ {gettext("Approval required")}
          </div>
          <div class="text-xs">
            <div>{gettext("tool:")} <code class="font-mono">{@pending_approval.tool_name}</code></div>
            <div>{gettext("risk:")} <code class="font-mono">{@pending_approval.risk_level}</code></div>
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
            <button type="submit" class="rounded bg-red-600 px-3 py-1 text-xs text-white hover:bg-red-700">
              {gettext("Deny")}
            </button>
          </form>
        </div>

        <div :if={@error} class="mt-2 rounded border border-red-400 dark:border-red-600 bg-red-50 dark:bg-red-950/40 p-2 text-xs text-red-700 dark:text-red-200">
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
            class="rounded bg-black px-4 py-2 text-sm text-white disabled:opacity-50"
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

  defp message(%{msg: %{"role" => "user"}} = assigns) do
    ~H"""
    <div class="max-w-[80%] whitespace-pre-wrap rounded-lg bg-blue-100 dark:bg-blue-900/40 px-3 py-2 text-sm">
      <div class="mb-1 font-mono text-[10px] uppercase opacity-60">{gettext("user")}</div>
      {@msg["content"]}
    </div>
    """
  end

  defp message(%{msg: %{"role" => "assistant", "tool_calls" => calls}} = assigns)
       when is_list(calls) and calls != [] do
    assigns = assign(assigns, :calls, calls)

    ~H"""
    <div class="max-w-[80%] space-y-1 rounded-lg border border-amber-300 dark:border-amber-700 bg-amber-50 dark:bg-amber-950/40 px-3 py-2 text-sm">
      <div class="font-mono text-[10px] uppercase opacity-60">{gettext("assistant · calling tools")}</div>
      <div :if={@msg["content"]} class="whitespace-pre-wrap">{@msg["content"]}</div>
      <ul class="space-y-1">
        <li :for={c <- @calls} class="font-mono text-xs">
          → {c["function"]["name"]}({trunc_text(c["function"]["arguments"], 140)})
        </li>
      </ul>
    </div>
    """
  end

  defp message(%{msg: %{"role" => "assistant"}} = assigns) do
    ~H"""
    <div class="max-w-[80%] whitespace-pre-wrap rounded-lg bg-base-200 px-3 py-2 text-sm">
      <div class="mb-1 font-mono text-[10px] uppercase opacity-60">{gettext("assistant")}</div>
      {@msg["content"]}
    </div>
    """
  end

  defp message(%{msg: %{"role" => "tool"}} = assigns) do
    ~H"""
    <div class="max-w-[80%] rounded-lg border border-emerald-300 dark:border-emerald-700 bg-emerald-50 dark:bg-emerald-950/40 px-3 py-2 text-sm">
      <div class="mb-1 font-mono text-[10px] uppercase opacity-60">{gettext("tool result")}</div>
      <pre class="overflow-x-auto whitespace-pre-wrap text-xs">{trunc_text(@msg["content"], 600)}</pre>
    </div>
    """
  end

  defp message(%{msg: msg} = assigns) do
    assigns = assign(assigns, :msg, msg)

    ~H"""
    <div class="max-w-[80%] rounded-lg bg-base-300 px-3 py-2 text-xs opacity-70">
      {inspect(@msg)}
    </div>
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

  defp trunc_text(nil, _n), do: ""

  defp trunc_text(text, n) when is_binary(text) do
    if String.length(text) > n, do: String.slice(text, 0, n) <> "…", else: text
  end

  defp trunc_text(other, n), do: trunc_text(inspect(other), n)
end
