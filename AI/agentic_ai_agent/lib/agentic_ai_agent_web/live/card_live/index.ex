defmodule AgenticAiAgentWeb.CardLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Design

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :cards, Design.list_cards_with_assocs())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header>
          <h1 class="text-2xl font-semibold">{gettext("Agentic Cards")}</h1>
          <p class="text-sm opacity-70">
            {gettext("Cards are the agent's behavioral contract. Authored as YAML under priv/cards/ and synced via mix run priv/repo/seeds.exs.")}
          </p>
        </header>

        <div :if={@cards == []} class="rounded border border-dashed p-6 text-center opacity-70">
          {gettext("No cards loaded yet. Run mix run priv/repo/seeds.exs.")}
        </div>

        <ul class="space-y-4">
          <li :for={card <- @cards} class="rounded-lg border p-4">
            <div class="flex items-baseline justify-between gap-3">
              <div>
                <.link navigate={~p"/cards/#{card.id}"} class="text-lg font-semibold hover:underline">
                  {card.name}
                </.link>
                <p class="font-mono text-xs opacity-60">{card.slug}</p>
              </div>
              <div class="text-xs opacity-70">
                {length(card.task_taxonomies)} {gettext("taxonomies")} · {length(card.workflow_graphs)} {gettext("workflows")}
              </div>
            </div>
            <p :if={card.goal} class="mt-2 text-sm opacity-80">{card.goal}</p>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
