defmodule AgenticAiAgent.Tools.Delegate do
  @moduledoc """
  Pseudo-tool: schema-only marker so the LLM knows how to ask for a sub-agent.
  The runtime intercepts calls to `delegate` before the registry sees them
  and spawns an isolated `Agent.Runtime` with its own conversation, optional
  skill body, and (optionally) a restricted tool allow-list.

  The sub-agent's final answer becomes this tool's `output` from the parent's
  perspective, keeping the parent's context window clean of the sub-agent's
  intermediate reasoning.
  """

  @behaviour AgenticAiAgent.Tool

  alias AgenticAiAgent.Skills

  @impl true
  def name, do: "delegate"

  @impl true
  def description do
    skill_lines =
      try do
        Skills.descriptors()
        |> Enum.map(fn s -> "- #{s.slug}: #{s.description}" end)
        |> Enum.join("\n")
      catch
        :exit, _ -> ""
      end

    base =
      "Spawn an isolated sub-agent to handle a focused sub-task. Use this when the work would benefit from a clean context or a specialised skill. The sub-agent's final answer is returned to you as a structured object."

    if skill_lines == "", do: base, else: base <> "\n\nAvailable skills:\n" <> skill_lines
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "required" => ["task"],
      "properties" => %{
        "task" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 4000,
          "description" => "Self-contained description of the sub-task in plain language."
        },
        "skill" => %{
          "type" => "string",
          "description" => "Optional skill slug to load as the sub-agent's system prompt."
        },
        "max_steps" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 20,
          "description" => "Cap on ReAct iterations for the sub-agent (default 6)."
        },
        "tools_allow" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "Optional whitelist of tool names the sub-agent may use."
        }
      }
    }
  end

  @impl true
  def output_schema do
    %{
      "type" => "object",
      "required" => ["summary"],
      "properties" => %{
        "summary" => %{"type" => "string"},
        "sub_run_id" => %{"type" => "string"}
      }
    }
  end

  @impl true
  def risk_level, do: :low

  @impl true
  def side_effects do
    [
      "Spawns a sub-agent runtime with its own Conversation and trace.",
      "Sub-agent inherits the parent's card but can have a restricted tool allow-list."
    ]
  end

  @impl true
  def failure_modes, do: ["sub_agent_failed"]

  @impl true
  def retry_policy, do: %{max_retries: 0}

  # The runtime intercepts `delegate` before the registry would dispatch.
  # If someone calls it directly, surface that mistake clearly.
  @impl true
  def call(_args),
    do: {:error, "delegate is dispatched by the runtime, not the tools registry"}
end
