defmodule AgenticAiAgentWeb.Diff do
  @moduledoc """
  Tiny line-based diff helper shared by the CardLive.History and
  SkillLive.History pages. Splits both inputs on newlines and runs Erlang's
  Myers diff (via `List.myers_difference/2`) to produce a `[{op, lines}]`
  list where `op` is `:eq | :del | :ins`.
  """

  @doc "Return a list of `{op, lines}` chunks where op is :eq | :del | :ins."
  @spec lines(String.t() | nil, String.t() | nil) :: [{atom(), [String.t()]}]
  def lines(nil, b), do: lines("", b || "")
  def lines(a, nil), do: lines(a, "")

  def lines(a, b) when is_binary(a) and is_binary(b) do
    a_lines = String.split(a, ~r/\r?\n/)
    b_lines = String.split(b, ~r/\r?\n/)
    List.myers_difference(a_lines, b_lines)
  end
end
