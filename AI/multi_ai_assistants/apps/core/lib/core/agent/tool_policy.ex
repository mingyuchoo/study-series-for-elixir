defmodule Core.Agent.ToolPolicy do
  @moduledoc "Compatibility boundary for the pure tool authorization policy."

  defdelegate restricted?(name), to: AgentDomain.ToolPolicy
  defdelegate authorize(name, opts), to: AgentDomain.ToolPolicy
end
