defmodule Core.Agent.FrontmatterParser do
  @moduledoc "Compatibility boundary for the pure frontmatter parser."

  defdelegate parse(text), to: AgentDomain.FrontmatterParser
  defdelegate parse_value(value), to: AgentDomain.FrontmatterParser
end
