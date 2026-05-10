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
  Light / Dark 테마 전환 토글 버튼.
  """
  def theme_toggle(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={JS.dispatch("phx:toggle-theme")}
      class="btn btn-ghost btn-sm btn-circle"
      title="테마 전환"
      aria-label="테마 전환"
    >
      <span class="theme-toggle-light">
        <.icon name="hero-sun-mini" class="size-5" />
      </span>
      <span class="theme-toggle-dark hidden">
        <.icon name="hero-moon-mini" class="size-5" />
      </span>
    </button>
    """
  end

  def theme_dropdown(assigns) do
    ~H"""
    <.theme_toggle />
    """
  end
end
