defmodule AgenticAiAgentWeb.ToolLive.Form do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Tools.Registry, as: ToolRegistry
  alias AgenticAiAgent.Tools.Specs

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    spec = Specs.get_spec!(id)
    changeset = Specs.change(spec)

    {:ok,
     socket
     |> assign(:spec, spec)
     |> assign(:form, to_form(changeset))
     |> assign(:retry_text, retry_to_text(spec.retry_policy))}
  end

  @impl true
  def handle_event("validate", %{"tool_spec" => params}, socket) do
    params = put_retry(params)

    changeset =
      socket.assigns.spec
      |> Specs.change(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:retry_text, params["retry_policy"] || socket.assigns.retry_text)}
  end

  def handle_event("save", %{"tool_spec" => params}, socket) do
    params = put_retry(params)

    case ToolRegistry.update_spec(socket.assigns.spec.name, params) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Tool settings saved."))
         |> push_navigate(to: ~p"/tools")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :form, to_form(cs))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, gettext("Save failed: %{r}.", r: inspect(reason)))}
    end
  end

  # ----- Helpers -----

  defp put_retry(params) do
    # The textarea name is server[retry_policy] — value is the raw JSON string.
    # Specs.update parses it.
    Map.put(params, "retry_policy", params["retry_policy"])
  end

  defp retry_to_text(nil), do: "{}"
  defp retry_to_text(map) when is_map(map), do: Jason.encode!(map, pretty: true)
  defp retry_to_text(other), do: inspect(other)

  # ----- Render -----

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="mx-auto max-w-2xl space-y-6">
        <header class="flex items-baseline justify-between">
          <div>
            <h1 class="text-2xl font-semibold">{gettext("Edit tool")}</h1>
            <code class="font-mono text-xs opacity-60">{@spec.name}</code>
          </div>
          <.link navigate={~p"/tools"} class="text-xs opacity-70 hover:underline">
            ← {gettext("Back")}
          </.link>
        </header>

        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
          <.input field={@form[:risk_level]} type="select" label={gettext("Risk level")}
            options={[{"low", "low"}, {"medium", "medium"}, {"high", "high"}, {"critical", "critical"}]} />

          <p class="-mt-3 text-[11px] opacity-60">
            {gettext("Risk level decides whether a call pauses for human approval (per card safety_policy).")}
          </p>

          <.input field={@form[:enabled]} type="checkbox" label={gettext("Enabled")} />

          <p class="-mt-3 text-[11px] opacity-60">
            {gettext("Disabled tools are hidden from the LLM and rejected at dispatch with {:error, :tool_disabled}.")}
          </p>

          <div>
            <label class="mb-1 block text-sm font-semibold">{gettext("Retry policy")} <span class="opacity-50">({gettext("JSON map")})</span></label>
            <textarea
              name="tool_spec[retry_policy]"
              rows="6"
              class="w-full rounded border px-2 py-1 font-mono text-xs"
              phx-debounce="200"
            >{@retry_text}</textarea>
            <p class="mt-1 text-[11px] opacity-60">
              {gettext("Common keys: max_retries, backoff_ms, jitter_ms, retry_on. Saved as JSON map.")}
            </p>
          </div>

          <div class="flex items-center gap-3 pt-2">
            <button type="submit" class="px-6 py-2 text-sm font-medium" style="background:#141413;color:#F3F0EE;border-radius:20px;letter-spacing:-0.02em;">
              {gettext("Save")}
            </button>
            <.link navigate={~p"/tools"} class="text-sm opacity-70 hover:underline">
              {gettext("Cancel")}
            </.link>
          </div>
        </.form>

        <details class="rounded border p-3">
          <summary class="cursor-pointer text-xs font-semibold uppercase tracking-wide opacity-70">
            {gettext("Read-only fields")}
          </summary>
          <dl class="mt-2 space-y-1 text-xs">
            <dt class="font-semibold">{gettext("purpose")}</dt>
            <dd class="opacity-80">{@spec.purpose}</dd>
            <dt class="mt-2 font-semibold">{gettext("side_effects")}</dt>
            <dd class="opacity-80">{@spec.side_effects}</dd>
            <dt class="mt-2 font-semibold">{gettext("failure_modes")}</dt>
            <dd class="opacity-80">{Enum.join(@spec.failure_modes || [], ", ")}</dd>
          </dl>
        </details>
      </div>
    </Layouts.app>
    """
  end
end
