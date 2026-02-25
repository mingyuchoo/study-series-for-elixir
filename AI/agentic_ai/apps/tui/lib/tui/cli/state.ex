defmodule TUI.CLI.State do
  @moduledoc """
  CLI 상태를 관리하는 구조체.
  """

  defstruct [
    :current_conversation_id,
    :current_conversation,
    conversations: [],
    messages: [],
    user_profile: nil
  ]

  @type t :: %__MODULE__{
          current_conversation_id: String.t() | nil,
          current_conversation: map() | nil,
          conversations: list(map()),
          messages: list(map()),
          user_profile: map() | nil
        }

  @doc """
  새로운 기본 State를 생성합니다.
  """
  def new do
    %__MODULE__{}
  end
end
