defmodule AgenticAiAgent.Memory.Embedding do
  @moduledoc """
  Float32-packed binary representation for embedding vectors, plus
  in-process cosine similarity. SQLite stores the packed binary directly
  so we don't need a vector extension.

  Layout: each float is encoded little-endian as a 32-bit IEEE-754 number,
  concatenated in order. Length(vector) = byte_size(binary) / 4.
  """

  @spec pack([float()]) :: binary()
  def pack(floats) when is_list(floats) do
    Enum.reduce(floats, <<>>, fn f, acc ->
      <<acc::binary, f::float-32-little>>
    end)
  end

  @spec unpack(binary()) :: [float()]
  def unpack(bin) when is_binary(bin), do: do_unpack(bin, [])

  defp do_unpack(<<>>, acc), do: Enum.reverse(acc)

  defp do_unpack(<<f::float-32-little, rest::binary>>, acc),
    do: do_unpack(rest, [f | acc])

  @doc """
  Cosine similarity between two equal-length float lists. Returns 0.0 if
  either vector has zero norm.
  """
  @spec cosine([float()], [float()]) :: float()
  def cosine(a, b) when is_list(a) and is_list(b) do
    {dot, na, nb} =
      Enum.zip_reduce(a, b, {0.0, 0.0, 0.0}, fn x, y, {d, ai, bi} ->
        {d + x * y, ai + x * x, bi + y * y}
      end)

    cond do
      na == 0.0 or nb == 0.0 -> 0.0
      true -> dot / (:math.sqrt(na) * :math.sqrt(nb))
    end
  end

  @doc """
  Cosine similarity between a query vector (list) and a packed binary.
  Avoids materializing the full list for each candidate when scanning.
  """
  @spec cosine_packed([float()], binary()) :: float()
  def cosine_packed(query, packed) when is_list(query) and is_binary(packed) do
    {dot, na, nb} = stream_dot(query, packed, 0.0, 0.0, 0.0)

    cond do
      na == 0.0 or nb == 0.0 -> 0.0
      true -> dot / (:math.sqrt(na) * :math.sqrt(nb))
    end
  end

  defp stream_dot([], <<>>, dot, na, nb), do: {dot, na, nb}

  defp stream_dot([x | rest], <<y::float-32-little, more::binary>>, dot, na, nb) do
    stream_dot(rest, more, dot + x * y, na + x * x, nb + y * y)
  end

  # Different lengths — treat as zero similarity rather than crash on bad data.
  defp stream_dot(_, _, _, _, _), do: {0.0, 0.0, 0.0}
end
