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
      <ul
        tabindex="0"
        class="menu menu-sm dropdown-content bg-base-100 z-40 mt-3 w-44 border border-base-300 p-2"
      >
        <li>
          <button
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme="light"
            class="flex items-center gap-2"
          >
            <.icon name="hero-sun-mini" class="size-4" /> Light
          </button>
        </li>
        <li>
          <button
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme="dark"
            class="flex items-center gap-2"
          >
            <.icon name="hero-moon-mini" class="size-4" /> Dark
          </button>
        </li>
        <li>
          <button
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme="system"
            class="flex items-center gap-2"
          >
            <.icon name="hero-computer-desktop-mini" class="size-4" /> System
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
