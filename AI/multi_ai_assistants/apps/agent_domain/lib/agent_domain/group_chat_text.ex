defmodule AgentDomain.GroupChatText do
  @moduledoc "Pure group chat transcript formatting and moderator response parsing."

  @transcript_excerpt_chars 800

  def format_transcript_for_moderator([]), do: "(아직 발언 없음 — 토론 시작)"

  def format_transcript_for_moderator(transcript) do
    Enum.map_join(transcript, "\n\n", fn entry ->
      content = String.slice(entry.content || "", 0, @transcript_excerpt_chars)

      tag =
        case entry.kind do
          :moderator_pick -> "[모더레이터]"
          :worker -> "[#{entry.display_name}]"
          :worker_error -> "[#{entry.display_name} ERROR]"
          :final -> "[최종]"
          _ -> "[?]"
        end

      "라운드 #{entry.round} #{tag}: #{content}"
    end)
  end

  def parse_moderator_output(content) do
    json_text =
      content
      |> String.trim()
      |> strip_code_fences()

    with {:ok, decoded} <- Jason.decode(json_text) do
      decision = Map.get(decoded, "decision")

      result = %{
        decision: decision,
        next_speaker: Map.get(decoded, "next_speaker"),
        instruction: Map.get(decoded, "instruction"),
        assignments: Map.get(decoded, "assignments"),
        reasoning: Map.get(decoded, "reasoning") || "",
        final_answer: Map.get(decoded, "final_answer")
      }

      {:ok, result}
    end
  end

  defp strip_code_fences(text) do
    text
    |> String.replace(~r/^```(?:json)?\n/, "")
    |> String.replace(~r/\n```\s*$/, "")
  end

  def restore_transcript(%{"entries" => entries}) when is_list(entries),
    do: restore_entries(entries)

  def restore_transcript(%{entries: entries}) when is_list(entries), do: restore_entries(entries)
  def restore_transcript(_), do: []

  defp restore_entries(entries) do
    Enum.map(entries, fn entry ->
      keys = [:kind, :round, :speaker, :display_name, :content, :reasoning, :instruction]

      Map.new(keys, fn key ->
        value = Map.get(entry, key) || Map.get(entry, Atom.to_string(key))

        value =
          if key == :kind and is_binary(value), do: String.to_existing_atom(value), else: value

        {key, value}
      end)
    end)
  end

  def format_transcript_for_worker([]), do: "(아직 발언 없음)"

  def format_transcript_for_worker(transcript) do
    transcript
    |> Enum.filter(&(&1.kind == :worker))
    |> case do
      [] ->
        "(워커 발언 아직 없음)"

      entries ->
        Enum.map_join(entries, "\n", fn entry ->
          excerpt = String.slice(entry.content || "", 0, @transcript_excerpt_chars)
          "- [#{entry.display_name}] #{excerpt}"
        end)
    end
  end

end
