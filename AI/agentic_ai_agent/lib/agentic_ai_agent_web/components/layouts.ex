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
      |> assign(:use_items, nav_use_items())
      |> assign(:setup_items, nav_setup_items())

    ~H"""
    <div class="flex min-h-screen flex-col md:flex-row">
      <!-- Sidebar: drawer on mobile (slide-in), sticky full-viewport on md+ -->
      <aside
        id="sidebar"
        class={[
          "flex flex-col bg-base-200",
          "fixed inset-y-0 left-0 z-50 w-64 -translate-x-full transform transition-transform duration-200",
          "md:sticky md:top-0 md:h-screen md:w-56 md:translate-x-0"
        ]}
        style="box-shadow: rgba(0,0,0,0.04) 4px 0 24px 0;"
        aria-label={gettext("Primary")}
      >
        <div class="flex items-center justify-between border-b border-base-300 p-4">
          <.link navigate={~p"/"} class="block" phx-click={close_drawer()}>
            <span class="text-[15px] font-medium" style="letter-spacing: -0.02em;">
              {gettext("Agentic AI Agent")}
            </span>
          </.link>
          <!-- Mobile close button -->
          <button
            type="button"
            class="md:hidden"
            aria-label={gettext("Close menu")}
            phx-click={close_drawer()}
          >
            <.icon name="hero-x-mark-micro" class="size-5 opacity-70" />
          </button>
        </div>

        <nav class="flex-1 overflow-y-auto px-2 py-3">
          <.nav_section
            label={gettext("Use")}
            items={@use_items}
            current_path={@current_path}
          />
          <.nav_section
            label={gettext("Setup")}
            items={@setup_items}
            current_path={@current_path}
          />
        </nav>

        <div class="flex items-center justify-between gap-2 border-t border-base-300 p-3">
          <.locale_toggle locale={@locale} current_path={@current_path} />
          <.theme_toggle />
        </div>
      </aside>

      <!-- Mobile backdrop (only visible when drawer is open) -->
      <div
        id="drawer-backdrop"
        class="fixed inset-0 z-40 hidden bg-black/30 md:hidden"
        phx-click={close_drawer()}
        aria-hidden="true"
      />

      <!-- Mobile top bar with hamburger -->
      <header class="flex items-center justify-between border-b border-base-300 bg-base-200 p-3 md:hidden">
        <div class="flex items-center gap-3">
          <button
            type="button"
            class="rounded-full p-1.5 hover:bg-base-300/40"
            aria-label={gettext("Open menu")}
            phx-click={open_drawer()}
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
          <.link navigate={~p"/"} class="text-base font-medium" style="letter-spacing: -0.02em;">
            {gettext("Agentic AI Agent")}
          </.link>
        </div>
        <div class="flex items-center gap-2">
          <.locale_toggle locale={@locale} current_path={@current_path} />
          <.theme_toggle />
        </div>
      </header>

      <main class="min-w-0 flex-1">
        <div class="mx-auto max-w-6xl px-4 py-8 sm:px-6 lg:px-8">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # ----- Mobile drawer JS commands -----

  defp open_drawer do
    %JS{}
    |> JS.remove_class("-translate-x-full", to: "#sidebar")
    |> JS.add_class("translate-x-0", to: "#sidebar")
    |> JS.show(to: "#drawer-backdrop")
  end

  defp close_drawer do
    %JS{}
    |> JS.remove_class("translate-x-0", to: "#sidebar")
    |> JS.add_class("-translate-x-full", to: "#sidebar")
    |> JS.hide(to: "#drawer-backdrop")
  end

  # ----- Sidebar nav section (collapsible) -----

  attr :label, :string, required: true
  attr :items, :list, required: true
  attr :current_path, :string, required: true

  defp nav_section(assigns) do
    assigns = assign(assigns, :open?, any_active?(assigns.items, assigns.current_path))

    ~H"""
    <details open={@open?} class="group mb-2">
      <summary class="flex cursor-pointer select-none items-center justify-between px-2 py-2 [&::-webkit-details-marker]:hidden">
        <span class="eyebrow">{@label}</span>
        <.icon
          name="hero-chevron-right-micro"
          class="size-3 opacity-60 transition-transform group-open:rotate-90"
        />
      </summary>
      <ul class="mt-1 space-y-1">
        <li :for={item <- @items}>
          <.link
            navigate={item.path}
            phx-click={close_drawer()}
            class={nav_item_class(active?(item.path, @current_path))}
            style={nav_item_style(active?(item.path, @current_path))}
          >
            {item.label.()}
          </.link>
        </li>
      </ul>
    </details>
    """
  end

  # Active item is the Ink Pill: cream text on warm-ink, 20px radius.
  defp nav_item_class(true),
    do:
      "block px-3 py-1.5 text-sm font-medium"

  defp nav_item_class(false),
    do:
      "block px-3 py-1.5 text-sm font-medium opacity-70 hover:opacity-100 hover:bg-base-300/40"

  defp nav_item_style(true),
    do: "background:#141413;color:#F3F0EE;border-radius:20px;letter-spacing:-0.02em;"

  defp nav_item_style(false),
    do: "border-radius:20px;letter-spacing:-0.02em;"

  defp any_active?(items, current_path),
    do: Enum.any?(items, &active?(&1.path, current_path))

  defp active?(item_path, current_path) when is_binary(item_path) and is_binary(current_path) do
    item_path == current_path or
      (item_path != "/" and String.starts_with?(current_path, item_path <> "/"))
  end

  defp active?(_, _), do: false

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
          if(@locale == code, do: "text-base-100 shadow-sm", else: "opacity-70 hover:opacity-100")
        ]}
        style={if @locale == code, do: "background:#141413;", else: nil}
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
