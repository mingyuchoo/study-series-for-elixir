defmodule PlayaWeb.PlayaComponents do
  @moduledoc """
  Provides Playa UI components
  """
  use Phoenix.Component
  # alias Phoenix.LiveView.JS
  # import PlayaWeb.Gettext

  @doc """
  Renders a button.

  ## Examples
      <.button>Click!</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def playa_button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3",
        "text-sm font-semibold leading-6 text-white active:text-white/80",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end
end
