defmodule AgenticAiAgentWeb.ProfileLive do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Accounts
  alias AgenticAiAgentWeb.Locale

  @themes ~w(system light dark)
  @avatar_upload_dir Path.expand("../../../priv/static/uploads/profiles", __DIR__)
  @avatar_upload_path "/uploads/profiles/"
  @avatar_extensions ~w(.gif .jpeg .jpg .png .webp)

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(
       :selected_path,
       user.avatar_path || AgenticAiAgentWeb.AgentProfiles.default_path(%{})
     )
     |> assign(:selected_locale, user.preferred_locale || Locale.default())
     |> assign(:selected_theme, user.preferred_theme || "system")
     |> allow_upload(:avatar,
       accept: @avatar_extensions,
       max_entries: 1,
       max_file_size: 5_000_000
     )
     |> assign_form(Accounts.change_user_profile(user))}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.current_user
      |> Accounts.change_user_profile(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:selected_path, socket.assigns.selected_path)
     |> apply_live_preferences(params)
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    params = put_avatar_path(socket, params)

    case Accounts.update_user_profile(socket.assigns.current_user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, user)
         |> assign(:selected_path, user.avatar_path)
         |> assign(:selected_locale, user.preferred_locale)
         |> assign(:selected_theme, user.preferred_theme)
         |> apply_live_preferences(%{
           "preferred_locale" => user.preferred_locale,
           "preferred_theme" => user.preferred_theme
         })
         |> assign_form(Accounts.change_user_profile(user))
         |> put_flash(:info, gettext("Profile saved."))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  defp apply_live_preferences(socket, params) do
    locale = selected_locale(params, socket.assigns.selected_locale)
    theme = selected_theme(params, socket.assigns.selected_theme)

    Gettext.put_locale(AgenticAiAgentWeb.Gettext, locale)

    socket
    |> assign(:locale, locale)
    |> assign(:selected_locale, locale)
    |> assign(:selected_theme, theme)
    |> push_event("set-saved-theme", %{theme: theme})
  end

  defp selected_locale(%{"preferred_locale" => locale}, fallback) do
    if locale in Locale.supported(), do: locale, else: fallback
  end

  defp selected_locale(_params, fallback), do: fallback

  defp selected_theme(%{"preferred_theme" => theme}, _fallback) when theme in @themes, do: theme
  defp selected_theme(_params, fallback), do: fallback

  defp put_avatar_path(socket, params) do
    avatar_path =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
        File.mkdir_p!(@avatar_upload_dir)

        filename = "#{Ecto.UUID.generate()}#{avatar_extension(entry.client_name)}"
        destination = Path.join(@avatar_upload_dir, filename)
        File.cp!(path, destination)

        {:ok, @avatar_upload_path <> filename}
      end)
      |> List.first()

    Map.put(params, "avatar_path", avatar_path || socket.assigns.selected_path)
  end

  defp avatar_extension(filename) do
    extension = filename |> Path.extname() |> String.downcase()
    if extension in @avatar_extensions, do: extension, else: ".png"
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :user))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_path={@current_path}
      locale={@locale}
      current_user={@current_user}
    >
      <div class="space-y-6">
        <header class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <div class="eyebrow mb-2">{gettext("Settings")}</div>
            <h1 class="text-2xl font-semibold">{gettext("Profile")}</h1>
            <p class="text-sm opacity-70">
              {gettext("Manage the profile shown for your signed-in account.")}
            </p>
          </div>
          <img
            src={@selected_path}
            alt=""
            class="h-16 w-16 rounded-full border border-base-300 bg-base-200 object-cover"
          />
        </header>

        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-5">
          <div class="grid gap-4 md:grid-cols-2">
            <div>
              <label class="text-xs font-semibold opacity-70">{gettext("Email")}</label>
              <input
                type="email"
                value={@current_user.email}
                disabled
                class="mt-1 w-full rounded border bg-base-200 px-3 py-2 text-sm opacity-70"
              />
            </div>
            <div>
              <label class="text-xs font-semibold opacity-70">{gettext("Display name")}</label>
              <.input field={@form[:display_name]} type="text" required />
            </div>
          </div>

          <div class="grid gap-4 md:grid-cols-2">
            <fieldset>
              <legend class="mb-2 text-xs font-semibold opacity-70">
                {gettext("Preferred language")}
              </legend>
              <div class="inline-flex rounded-full border border-base-300 bg-base-200 p-1 text-xs">
                <label
                  :for={code <- Locale.supported()}
                  class={[
                    "cursor-pointer rounded-full px-3 py-1.5 transition",
                    @selected_locale == code && "bg-primary text-primary-content",
                    @selected_locale != code && "opacity-70 hover:opacity-100"
                  ]}
                >
                  <input
                    type="radio"
                    name="user[preferred_locale]"
                    value={code}
                    checked={@selected_locale == code}
                    class="sr-only"
                  />
                  {Locale.labels()[code] || code}
                </label>
              </div>
            </fieldset>

            <fieldset>
              <legend class="mb-2 text-xs font-semibold opacity-70">
                {gettext("Preferred theme")}
              </legend>
              <div class="inline-flex rounded-full border border-base-300 bg-base-200 p-1 text-xs">
                <label
                  :for={
                    {theme, label} <- [
                      {"system", gettext("System")},
                      {"light", gettext("Light")},
                      {"dark", gettext("Dark")}
                    ]
                  }
                  class={[
                    "cursor-pointer rounded-full px-3 py-1.5 transition",
                    @selected_theme == theme && "bg-primary text-primary-content",
                    @selected_theme != theme && "opacity-70 hover:opacity-100"
                  ]}
                >
                  <input
                    type="radio"
                    name="user[preferred_theme]"
                    value={theme}
                    checked={@selected_theme == theme}
                    class="sr-only"
                  />
                  {label}
                </label>
              </div>
            </fieldset>
          </div>

          <div class="max-w-md">
            <label class="mb-2 block text-xs font-semibold opacity-70">
              {gettext("Profile photo")}
            </label>
            <div class="flex items-center gap-4 rounded-lg border border-base-300 bg-base-200 p-3">
              <div class="shrink-0">
                <%= if Enum.any?(@uploads.avatar.entries) do %>
                  <.live_img_preview
                    entry={List.first(@uploads.avatar.entries)}
                    class="h-16 w-16 rounded-full border border-base-300 bg-base-100 object-cover"
                  />
                <% else %>
                  <img
                    src={@selected_path}
                    alt=""
                    class="h-16 w-16 rounded-full border border-base-300 bg-base-100 object-cover"
                  />
                <% end %>
              </div>

              <div class="min-w-0 flex-1">
                <.live_file_input
                  upload={@uploads.avatar}
                  class="block w-full text-sm file:mr-3 file:rounded file:border-0 file:bg-primary file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-primary-content"
                />
                <p class="mt-2 text-xs opacity-60">
                  {gettext("JPG, PNG, GIF, or WebP up to 5 MB.")}
                </p>
                <p
                  :for={error <- upload_errors(@uploads.avatar)}
                  class="mt-1 text-xs text-error"
                >
                  {upload_error(error)}
                </p>
              </div>
            </div>
          </div>

          <div class="flex justify-end">
            <button
              type="submit"
              class="rounded bg-primary px-4 py-1.5 text-sm font-medium text-primary-content hover:opacity-90"
            >
              {gettext("Save profile")}
            </button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp upload_error(:too_large), do: gettext("The selected image is too large.")
  defp upload_error(:too_many_files), do: gettext("Select one image.")
  defp upload_error(:not_accepted), do: gettext("Select a supported image file.")
  defp upload_error(_), do: gettext("The image could not be uploaded.")
end
