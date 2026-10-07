defmodule AgentDomain.FrontmatterParser do
  @moduledoc """
  Agent/Skill markdown frontmatter에서 사용하는 작은 key-value 파서입니다.

  지원 범위는 현재 설정 파일에서 쓰는 단순 scalar, 최상위 list,
  한 단계 nested map으로 제한합니다.
  """

  def parse(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.map(&parse_line/1)
    |> Enum.reject(&match?(:skip, &1))
    |> do_parse(%{}, nil, nil)
    |> restore_list_order()
  end

  def parse_value(value) do
    cond do
      value =~ ~r/^\d+\.\d+$/ -> String.to_float(value)
      value =~ ~r/^\d+$/ -> String.to_integer(value)
      value in ["true", "false"] -> value == "true"
      true -> value
    end
  end

  defp do_parse([], acc, _current_list_key, _current_map_key), do: acc

  defp do_parse([{:list_item, value} | rest], acc, current_list_key, _current_map_key)
       when is_binary(current_list_key) do
    acc
    |> Map.update(current_list_key, [value], &[value | &1])
    |> then(&do_parse(rest, &1, current_list_key, nil))
  end

  defp do_parse([{:list_item, _value} | rest], acc, _current_list_key, _current_map_key) do
    do_parse(rest, acc, nil, nil)
  end

  defp do_parse([{:nested_pair, key, value} | rest], acc, _current_list_key, current_map_key)
       when is_binary(current_map_key) do
    updated =
      update_in(acc, [Access.key(current_map_key, %{})], &Map.put(&1, key, parse_value(value)))

    do_parse(rest, updated, nil, current_map_key)
  end

  defp do_parse([{:nested_pair, _key, _value} | rest], acc, current_list_key, current_map_key) do
    do_parse(rest, acc, current_list_key, current_map_key)
  end

  defp do_parse([{:pair, key, ""} | rest], acc, _current_list_key, _current_map_key) do
    case next_container(rest) do
      :list -> do_parse(rest, acc, key, nil)
      :nested -> do_parse(rest, Map.put(acc, key, %{}), nil, key)
      :none -> do_parse(rest, acc, key, nil)
    end
  end

  defp do_parse([{:pair, key, value} | rest], acc, _current_list_key, _current_map_key) do
    do_parse(rest, Map.put(acc, key, parse_value(value)), nil, nil)
  end

  defp parse_line(line) do
    trimmed = String.trim(line)
    indent = String.length(line) - String.length(String.trim_leading(line))

    cond do
      trimmed == "" ->
        :skip

      String.starts_with?(trimmed, "- ") ->
        {:list_item, String.trim_leading(trimmed, "- ")}

      indent > 0 ->
        parse_pair(trimmed, :nested_pair)

      true ->
        parse_pair(trimmed, :pair)
    end
  end

  defp parse_pair(line, tag) do
    case String.split(line, ":", parts: 2) do
      [key, value] -> {tag, String.trim(key), String.trim(value)}
      _ -> :skip
    end
  end

  defp next_container([{:list_item, _} | _]), do: :list
  defp next_container([{:nested_pair, _, _} | _]), do: :nested
  defp next_container(_lines), do: :none

  defp restore_list_order(frontmatter) do
    Map.new(frontmatter, fn
      {key, value} when is_list(value) -> {key, Enum.reverse(value)}
      pair -> pair
    end)
  end
end
