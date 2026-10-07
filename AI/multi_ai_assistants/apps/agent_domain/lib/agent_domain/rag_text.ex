defmodule AgentDomain.RagText do
  @moduledoc "Pure text chunking, lexical embedding, and result fusion for RAG."

  @embedding_dim 384
  @chunk_size 1_200
  @chunk_overlap 180

  def fuse_results(vector_results, lexical_results) do
    [vector_results, lexical_results]
    |> Enum.reduce(%{}, fn results, acc ->
      results
      |> Enum.with_index(1)
      |> Enum.reduce(acc, fn {result, rank}, scores ->
        key = {result.rag_id, result.position}

        Map.update(scores, key, Map.put(result, :score, 1 / (60 + rank)), fn existing ->
          %{existing | score: existing.score + 1 / (60 + rank)}
        end)
      end)
    end)
    |> Map.values()
  end

  def chunk_text(content) do
    content
    |> String.replace("\r\n", "\n")
    |> String.replace(~r/[ \t]+/, " ")
    |> String.trim()
    |> do_chunk([])
    |> Enum.reverse()
  end

  defp do_chunk("", acc), do: acc

  defp do_chunk(text, acc) do
    chunk = String.slice(text, 0, @chunk_size) |> String.trim()

    remaining =
      String.slice(text, max(String.length(chunk) - @chunk_overlap, 0), String.length(text))

    cond do
      chunk == "" -> acc
      String.length(text) <= @chunk_size -> [chunk | acc]
      true -> do_chunk(remaining, [chunk | acc])
    end
  end

  def embed_text(text) do
    tokens =
      Regex.scan(~r/[\p{L}\p{N}_-]+/u, String.downcase(text), capture: :first) |> List.flatten()

    vector = List.duplicate(0.0, @embedding_dim)

    tokens
    |> Enum.reduce(vector, fn token, acc ->
      index = :erlang.phash2(token, @embedding_dim)
      weight = 1.0 + :math.log(String.length(token) + 1)
      List.update_at(acc, index, &(&1 + weight))
    end)
    |> normalize()
  end

  defp normalize(vector) do
    norm =
      vector
      |> Enum.reduce(0.0, &(&2 + &1 * &1))
      |> :math.sqrt()

    if norm == 0.0 do
      vector
    else
      Enum.map(vector, &(&1 / norm))
    end
  end

end
