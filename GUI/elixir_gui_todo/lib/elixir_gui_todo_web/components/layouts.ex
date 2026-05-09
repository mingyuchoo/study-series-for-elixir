defmodule ElixirGuiTodoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ElixirGuiTodoWeb, :html

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

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-50 text-zinc-950 antialiased transition-colors dark:bg-zinc-950 dark:text-zinc-50">
      <header class="border-b border-zinc-200 bg-white/85 px-4 py-3 backdrop-blur dark:border-zinc-800 dark:bg-zinc-950/85 sm:px-6 lg:px-8">
        <div class="mx-auto flex max-w-6xl items-center justify-between gap-4">
          <a
            id="app-home-link"
            href="/"
            class="flex items-center gap-3 rounded-md focus:outline-none focus:ring-2 focus:ring-cyan-500 focus:ring-offset-2 dark:focus:ring-offset-zinc-950"
          >
            <span class="flex size-9 items-center justify-center rounded-md bg-zinc-950 text-white dark:bg-white dark:text-zinc-950">
              <.icon name="hero-check" class="size-5" />
            </span>
            <span class="text-sm font-semibold tracking-tight">Elixir Todo</span>
          </a>

          <.theme_toggle />
        </div>
      </header>

      <main>
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
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
    <div
      id="theme-toggle"
      class="relative grid grid-cols-3 rounded-md border border-zinc-200 bg-zinc-100 p-1 dark:border-zinc-800 dark:bg-zinc-900"
    >
      <div class="absolute inset-y-1 left-1 w-[calc((100%-0.5rem)/3)] rounded bg-white shadow-sm transition-[left] [[data-theme=light]_&]:left-[calc((100%-0.5rem)/3+0.25rem)] [[data-theme=dark]_&]:left-[calc((100%-0.5rem)*2/3+0.25rem)] dark:bg-zinc-800" />

      <button
        id="theme-system"
        type="button"
        class="relative flex size-8 cursor-pointer items-center justify-center rounded text-zinc-600 transition hover:text-zinc-950 dark:text-zinc-300 dark:hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Use system theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        id="theme-light"
        type="button"
        class="relative flex size-8 cursor-pointer items-center justify-center rounded text-zinc-600 transition hover:text-zinc-950 dark:text-zinc-300 dark:hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Use light theme"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        id="theme-dark"
        type="button"
        class="relative flex size-8 cursor-pointer items-center justify-center rounded text-zinc-600 transition hover:text-zinc-950 dark:text-zinc-300 dark:hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Use dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
