defmodule AgenticAiAgentWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use AgenticAiAgentWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_path, :string, default: "/", doc: "path of the current page, used by the locale toggle"
  attr :locale, :string, default: nil, doc: "currently active locale (`en` | `ko`)"

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign_new(:current_path, fn -> "/" end)
      |> assign_new(:locale, fn -> Gettext.get_locale(AgenticAiAgentWeb.Gettext) end)

    ~H"""
    <header class="border-b bg-base-100">
      <div class="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-3 sm:px-6 lg:px-8">
        <.link navigate={~p"/"} class="flex items-center gap-2">
          <span class="text-lg font-semibold tracking-tight">{gettext("Agentic AI Agent")}</span>
        </.link>

        <nav class="hidden flex-1 md:block" aria-label={gettext("Primary")}>
          <ul class="flex items-center justify-center gap-0.5 text-sm">
            <li class="mr-1 text-[10px] font-semibold uppercase tracking-wider opacity-40">
              {gettext("Use")}
            </li>
            <li :for={item <- nav_use_items()}>
              <.link
                navigate={item.path}
                class="block rounded px-3 py-1.5 text-sm font-medium opacity-75 hover:bg-base-200 hover:opacity-100"
              >
                {item.label.()}
              </.link>
            </li>

            <li class="mx-2 h-5 w-px bg-base-300" aria-hidden="true"></li>

            <li class="mr-1 text-[10px] font-semibold uppercase tracking-wider opacity-40">
              {gettext("Setup")}
            </li>
            <li :for={item <- nav_setup_items()}>
              <.link
                navigate={item.path}
                class="block rounded px-3 py-1.5 text-sm font-medium opacity-75 hover:bg-base-200 hover:opacity-100"
              >
                {item.label.()}
              </.link>
            </li>
          </ul>
        </nav>

        <div class="flex items-center gap-2">
          <.locale_toggle locale={@locale} current_path={@current_path} />
          <.theme_toggle />
        </div>
      </div>
    </header>

    <main class="mx-auto max-w-6xl px-4 py-8 sm:px-6 lg:px-8">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  # Labels are wrapped in a fn/0 so the active locale is consulted on every
  # render rather than at module-compile time.

  defp nav_use_items do
    [
      %{label: fn -> gettext("Chat") end, path: ~p"/chat"},
      %{label: fn -> gettext("Runs") end, path: ~p"/runs"},
      %{label: fn -> gettext("Memories") end, path: ~p"/memories"},
      %{label: fn -> gettext("Failures") end, path: ~p"/failures"}
    ]
  end

  defp nav_setup_items do
    [
      %{label: fn -> gettext("Cards") end, path: ~p"/cards"},
      %{label: fn -> gettext("Skills") end, path: ~p"/skills"},
      %{label: fn -> gettext("MCP") end, path: ~p"/mcp"},
      %{label: fn -> gettext("Evals") end, path: ~p"/evals"},
      %{label: fn -> gettext("Tools") end, path: ~p"/tools"}
    ]
  end

  attr :locale, :string, required: true
  attr :current_path, :string, default: "/"

  def locale_toggle(assigns) do
    assigns = assign(assigns, :labels, AgenticAiAgentWeb.Locale.labels())

    ~H"""
    <div class="flex items-center rounded-full border bg-base-100 p-0.5 text-xs">
      <.link
        :for={code <- AgenticAiAgentWeb.Locale.supported()}
        href={~p"/locale/#{code}?#{[return_to: @current_path]}"}
        class={[
          "rounded-full px-2.5 py-1 transition",
          if(@locale == code, do: "bg-black text-white shadow-sm", else: "opacity-70 hover:opacity-100")
        ]}
      >
        {@labels[code] || code}
      </.link>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
