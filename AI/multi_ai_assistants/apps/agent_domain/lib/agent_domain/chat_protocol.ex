defmodule AgentDomain.ChatProtocol do
  @moduledoc "Pure formatting and tool-call delta assembly for LLM messages."

  def merge_tool_call_delta(nil, tc) do
    %{
      "id" => tc["id"] || "",
      "type" => tc["type"] || "function",
      "function" => %{
        "name" => get_in(tc, ["function", "name"]) || "",
        "arguments" => get_in(tc, ["function", "arguments"]) || ""
      }
    }
  end

  def merge_tool_call_delta(existing_tc, tc) do
    func = existing_tc["function"]
    new_func = tc["function"] || %{}

    %{
      existing_tc
      | "id" => tc["id"] || existing_tc["id"],
        "function" => %{
          "name" => (new_func["name"] || "") <> (func["name"] || ""),
          "arguments" => (func["arguments"] || "") <> (new_func["arguments"] || "")
        }
    }
  end

  def append_item(list, item), do: List.insert_at(list, -1, item)

  def format_messages_for_api(messages) do
    Enum.map(messages, fn msg ->
      base = %{role: msg.role, content: msg.content}

      base
      |> maybe_add(:tool_calls, msg[:tool_calls])
      |> maybe_add(:tool_call_id, msg[:tool_call_id])
    end)
  end

  def format_tools_for_api(tools) do
    Enum.map(tools, fn tool ->
      %{
        type: "function",
        function: %{
          name: tool.name,
          description: tool.description,
          parameters: tool.parameters
        }
      }
    end)
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, _key, []), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
