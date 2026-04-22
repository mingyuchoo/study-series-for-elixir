defmodule WebWeb.Layouts do
  @moduledoc """
  애플리케이션 레이아웃 컴포넌트 모음.
  """
  use WebWeb, :html

  embed_templates "layouts/*"

  @doc """
  플래시 메시지 토스트 그룹.
  """
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""}, to: "#client-error")}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""}, to: "#server-error")}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  테마(Light / Dark / System) 전환 드롭다운. daisyUI dropdown + heroicons 기반.
  """
  def theme_dropdown(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-ghost btn-sm btn-circle" title="테마">
        <.icon name="hero-swatch" class="size-5" />
      </div>
      <ul tabindex="0" class="menu menu-sm dropdown-content bg-base-100 rounded-box z-40 mt-3 w-44 p-2 shadow">
        <li>
          <button phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="light" class="flex items-center gap-2">
            <.icon name="hero-sun-mini" class="size-4" /> Light
          </button>
        </li>
        <li>
          <button phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="dark" class="flex items-center gap-2">
            <.icon name="hero-moon-mini" class="size-4" /> Dark
          </button>
        </li>
        <li>
          <button phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="system" class="flex items-center gap-2">
            <.icon name="hero-computer-desktop-mini" class="size-4" /> System
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
