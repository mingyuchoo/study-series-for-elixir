defmodule AgenticAiAgentWeb.CardLive.ProfileSettings do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Design
  alias AgenticAiAgentWeb.AgentProfiles

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    card = Design.get_card!(id)

    {:ok,
     socket
     |> assign(:card, card)
     |> assign(:avatar_paths, AgentProfiles.paths())
     |> assign(:selected_path, AgentProfiles.default_path(card))
     |> assign(:source_path, relative_source_path(card.slug))}
  end

  @impl true
  def handle_event("preview_profile", %{"agent_avatar_path" => path}, socket) do
    if AgentProfiles.valid_path?(path) do
      {:noreply, assign(socket, :selected_path, path)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_profile", %{"agent_avatar_path" => path}, socket) do
    cond do
      not AgentProfiles.valid_path?(path) ->
        {:noreply, put_flash(socket, :error, gettext("Choose a valid profile image."))}

      is_nil(Design.card_source_path(socket.assigns.card.slug)) ->
        {:noreply, put_flash(socket, :error, gettext("Card source YAML was not found."))}

      true ->
        save_profile(socket, path)
    end
  end

  def handle_event("save_profile", _params, socket),
    do: {:noreply, put_flash(socket, :error, gettext("Choose a profile image."))}

  defp save_profile(socket, path) do
    card = socket.assigns.card
    source_path = Design.card_source_path(card.slug)

    change = %{
      "agent_avatar_path" => path,
      "agent_avatar_options" => AgentProfiles.paths()
    }

    with {:ok, source_yaml} <- File.read(source_path),
         {:ok, new_yaml} <- Design.apply_metadata_change(source_yaml, change),
         {:ok, %{card: updated_card}} <-
           Design.save_card_source(card.slug, new_yaml, reason: "update profile settings") do
      {:noreply,
       socket
       |> assign(:card, updated_card)
       |> assign(:selected_path, AgentProfiles.default_path(updated_card))
       |> assign(:source_path, relative_source_path(updated_card.slug))
       |> put_flash(:info, gettext("Profile settings saved."))}
    else
      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Could not save profile settings: %{reason}", reason: inspect(reason))
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="space-y-1">
          <div class="text-sm opacity-70">
            <.link navigate={~p"/cards"} class="hover:underline">{gettext("Settings")}</.link>
            <span>/</span>
            <.link navigate={~p"/cards"} class="hover:underline">{gettext("Agentic Cards")}</.link>
            <span>/</span>
            <span>{gettext("Profile settings")}</span>
          </div>
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h1 class="text-2xl font-semibold">{gettext("Profile settings")}</h1>
              <p class="font-mono text-xs opacity-60">{@card.slug}</p>
              <p :if={@source_path} class="font-mono text-[11px] opacity-50">
                {gettext("source:")} {@source_path}
              </p>
            </div>
            <img
              src={@selected_path}
              alt=""
              class="h-16 w-16 rounded-full border border-base-300 bg-base-200 object-cover"
            />
          </div>
        </header>

        <form
          id="profile-settings-form"
          phx-change="preview_profile"
          phx-submit="save_profile"
          class="space-y-4"
        >
          <div class="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-7">
            <label
              :for={path <- @avatar_paths}
              class={[
                "cursor-pointer rounded-lg border bg-base-200 p-3 transition hover:border-base-content",
                @selected_path == path && "border-base-content ring-2 ring-base-content",
                @selected_path != path && "border-base-300"
              ]}
            >
              <input
                type="radio"
                name="agent_avatar_path"
                value={path}
                checked={@selected_path == path}
                class="sr-only"
              />
              <img
                src={path}
                alt=""
                class="mx-auto h-20 w-20 rounded-full border border-base-300 bg-base-100 object-cover"
              />
              <div class="mt-2 text-center text-xs opacity-70">
                {gettext("Profile")} {AgentProfiles.number(path)}
              </div>
            </label>
          </div>

          <div class="flex items-center justify-end gap-2">
            <.link
              navigate={~p"/cards/#{@card.id}"}
              class="rounded border px-3 py-1.5 text-sm hover:bg-base-200"
            >
              {gettext("Cancel")}
            </.link>
            <button
              type="submit"
              class="rounded bg-primary px-4 py-1.5 text-sm font-medium text-primary-content hover:opacity-90"
            >
              {gettext("Save profile")}
            </button>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end

  defp relative_source_path(slug) do
    case Design.card_source_path(slug) do
      nil -> nil
      path -> relative_path(path)
    end
  end

  defp relative_path(absolute) do
    case String.split(absolute, "/priv/", parts: 2) do
      [_, rest] -> "priv/" <> rest
      _ -> absolute
    end
  end
end
