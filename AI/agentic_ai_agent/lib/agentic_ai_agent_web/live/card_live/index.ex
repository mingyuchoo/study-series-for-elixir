defmodule AgenticAiAgentWeb.CardLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Design

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :cards, Design.list_cards_with_assocs())}
  end

  @impl true
  def handle_event("reload_cards", _params, socket) do
    results = Design.load_cards_from_priv()

    {ok_results, err_results} =
      Enum.split_with(results, fn {_path, outcome} -> match?({:ok, _}, outcome) end)

    flash_kind = if err_results == [], do: :info, else: :error

    flash_msg =
      cond do
        results == [] ->
          gettext("No card YAML files found under priv/cards/.")

        err_results == [] ->
          gettext("Reloaded %{n} card(s) from priv/cards/.", n: length(ok_results))

        true ->
          first_err = err_results |> List.first() |> elem(1) |> elem(1) |> inspect()

          gettext(
            "Reloaded %{ok}, %{fail} failed. First error: %{err}",
            ok: length(ok_results),
            fail: length(err_results),
            err: String.slice(first_err, 0, 160)
          )
      end

    {:noreply,
     socket
     |> put_flash(flash_kind, flash_msg)
     |> assign(:cards, Design.list_cards_with_assocs())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="flex items-baseline justify-between gap-3">
          <div>
            <div class="eyebrow mb-2">{gettext("Cards")}</div>
            <h1 class="text-2xl font-semibold">{gettext("Agentic Cards")}</h1>
            <p class="text-sm opacity-70">
              {gettext("Cards are authored as YAML under priv/cards/. The database is a cache — use the button to re-sync after editing files.")}
            </p>
          </div>
          <button
            phx-click="reload_cards"
            type="button"
            class="rounded border px-3 py-1 text-xs hover:bg-base-200"
          >
            {gettext("Reload from files")}
          </button>
        </header>

        <div :if={@cards == []} class="rounded border border-dashed p-6 text-center opacity-70">
          {gettext("No cards loaded yet. Add a YAML file under priv/cards/ then press Reload.")}
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
