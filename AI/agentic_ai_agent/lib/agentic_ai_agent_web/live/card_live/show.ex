defmodule AgenticAiAgentWeb.CardLive.Show do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Design
  alias AgenticAiAgentWeb.AgentProfiles

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    card = Design.get_card!(id)
    {source_path, source_yaml} = load_source(card.slug)

    {:ok,
     socket
     |> assign(:card, card)
     |> assign(:source_path, source_path)
     |> assign(:source_yaml, source_yaml)}
  end

  defp load_source(slug) do
    dir = Application.app_dir(:agentic_ai_agent, "priv/cards")

    Enum.find_value([".yaml", ".yml"], {nil, nil}, fn ext ->
      path = Path.join(dir, "#{slug}#{ext}")

      case File.read(path) do
        {:ok, body} -> {relative_path(path), body}
        {:error, _} -> nil
      end
    end)
  end

  defp relative_path(absolute) do
    case String.split(absolute, "/priv/", parts: 2) do
      [_, rest] -> "priv/" <> rest
      _ -> absolute
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="space-y-1">
          <.link navigate={~p"/cards"} class="text-sm opacity-70 hover:underline">
            &larr; {gettext("Cards")}
          </.link>
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="flex items-start gap-3">
              <img
                src={AgentProfiles.default_path(@card)}
                alt=""
                class="h-12 w-12 rounded-full border border-base-300 bg-base-200 object-cover"
              />
              <div>
                <h1 class="text-2xl font-semibold">{@card.name}</h1>
                <p class="font-mono text-xs opacity-60">{@card.slug}</p>
                <p :if={@source_path} class="font-mono text-[11px] opacity-50">
                  {gettext("source:")} {@source_path}
                </p>
              </div>
            </div>
            <.link
              navigate={~p"/cards/#{@card.id}/profile"}
              class="rounded border px-3 py-1 text-xs hover:bg-base-200"
            >
              {gettext("Profile settings")}
            </.link>
            <.link
              navigate={~p"/chat?card=#{@card.slug}"}
              class="rounded border px-3 py-1 text-xs hover:bg-base-200"
            >
              {gettext("Chat with this card")}
            </.link>
          </div>
        </header>

        <details :if={@source_yaml} class="rounded border">
          <summary class="flex cursor-pointer items-center justify-between gap-2 px-3 py-2 text-xs font-semibold uppercase tracking-wide opacity-70">
            <span>{gettext("Source YAML")}</span>
            <span class="flex gap-2">
              <.link
                navigate={~p"/cards/#{@card.id}/profile"}
                class="rounded border px-2 py-0.5 text-[10px] hover:bg-base-200"
              >
                {gettext("Profile")}
              </.link>
              <.link
                navigate={~p"/cards/#{@card.id}/edit-source"}
                class="rounded border px-2 py-0.5 text-[10px] hover:bg-base-200"
              >
                {gettext("Edit")}
              </.link>
              <.link
                navigate={~p"/cards/#{@card.id}/history"}
                class="rounded border px-2 py-0.5 text-[10px] hover:bg-base-200"
              >
                {gettext("History")}
              </.link>
            </span>
          </summary>
          <pre class="overflow-x-auto bg-base-200 p-3 text-xs"><code>{@source_yaml}</code></pre>
        </details>

        <.section title={gettext("Role")}>
          <pre class="whitespace-pre-wrap text-sm">{@card.role}</pre>
        </.section>

        <.section title={gettext("Goal")}>
          <pre class="whitespace-pre-wrap text-sm">{@card.goal}</pre>
        </.section>

        <.section title={gettext("Scope")}>
          <pre class="whitespace-pre-wrap text-sm">{@card.scope}</pre>
        </.section>

        <.section title={gettext("Tool Policy")}>
          <.json_block value={@card.tool_policy} />
        </.section>

        <.section title={gettext("Reasoning Policy")}>
          <.json_block value={@card.reasoning_policy} />
        </.section>

        <.section title={gettext("Safety Policy")}>
          <.json_block value={@card.safety_policy} />
        </.section>

        <.section title={gettext("Output Contract")}>
          <.json_block value={@card.output_contract} />
        </.section>

        <.section title={gettext("Evaluation Mapping")}>
          <.json_block value={@card.evaluation_mapping} />
        </.section>

        <.section title={gettext("Task Taxonomies")}>
          <ul class="space-y-2">
            <li :for={t <- @card.task_taxonomies} class="rounded border p-3 text-sm">
              <div class="flex justify-between font-mono text-xs opacity-70">
                <span>{t.task_type}</span>
                <span>
                  {gettext("risk:")} {t.risk_level} · {gettext("complexity:")} {t.complexity}
                </span>
              </div>
              <p class="mt-1">{t.success_criteria}</p>
              <p class="mt-1 text-xs opacity-70">
                {gettext("tools:")} {Enum.join(t.required_tools, ", ")}
              </p>
            </li>
          </ul>
        </.section>

        <.section :if={@card.capability_matrix} title={gettext("Capability Matrix")}>
          <ul class="space-y-1 text-sm">
            <li>
              <b>{gettext("capabilities:")}</b> {Enum.join(
                @card.capability_matrix.supported_capabilities,
                ", "
              )}
            </li>
            <li>
              <b>{gettext("inputs:")}</b> {Enum.join(@card.capability_matrix.supported_inputs, ", ")}
            </li>
            <li>
              <b>{gettext("outputs:")}</b> {Enum.join(@card.capability_matrix.supported_outputs, ", ")}
            </li>
            <li>
              <b>{gettext("required tools:")}</b> {Enum.join(
                @card.capability_matrix.required_tools,
                ", "
              )}
            </li>
            <li><b>{gettext("constraints:")}</b> {@card.capability_matrix.constraints}</li>
            <li><b>{gettext("limitations:")}</b> {@card.capability_matrix.known_limitations}</li>
          </ul>
        </.section>

        <.section title={gettext("Workflow Graphs")}>
          <div :for={wf <- @card.workflow_graphs} class="space-y-2">
            <h3 class="font-mono text-sm">{wf.name}</h3>
            <.json_block value={
              %{
                states: wf.states,
                transitions: wf.transitions,
                terminal_states: wf.terminal_states,
                approval_points: wf.approval_points
              }
            } />
          </div>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section class="space-y-2">
      <h2 class="text-sm font-semibold uppercase tracking-wide opacity-70">{@title}</h2>
      <div>{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :value, :any, required: true

  defp json_block(assigns) do
    ~H"""
    <pre class="overflow-x-auto rounded bg-base-200 p-3 text-xs"><code>{format(@value)}</code></pre>
    """
  end

  defp format(nil), do: "—"
  defp format(value), do: Jason.encode!(value, pretty: true)
end
