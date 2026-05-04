defmodule Core.Contexts.VectorRags do
  @moduledoc """
  HNSWLib 기반 Vector RAG 인덱스를 관리합니다.
  """

  import Ecto.Query, warn: false

  alias Core.Repo
  alias Core.Schema.{VectorRag, VectorRagChunk}

  @embedding_dim 384
  @chunk_size 1_200
  @chunk_overlap 180
  @default_k 4

  def list_vector_rags do
    from(r in VectorRag, order_by: [asc: r.name])
    |> Repo.all()
  end

  def list_active_vector_rags do
    from(r in VectorRag, where: r.enabled == true, order_by: [asc: r.name])
    |> Repo.all()
  end

  def get_vector_rag!(id), do: Repo.get!(VectorRag, id)

  def change_vector_rag(%VectorRag{} = vector_rag, attrs \\ %{}) do
    VectorRag.changeset(vector_rag, attrs)
  end

  def create_vector_rag(attrs, source) do
    with {:ok, content} <- read_source(source),
         chunks when chunks != [] <- chunk_text(content),
         {:ok, vector_rag} <- insert_vector_rag(attrs, source, length(chunks)),
         {:ok, index_path} <- build_index(vector_rag.id, chunks),
         {:ok, vector_rag} <- update_vector_rag(vector_rag, %{index_path: index_path}),
         :ok <- insert_chunks(vector_rag.id, chunks) do
      {:ok, vector_rag}
    else
      [] -> {:error, :empty_document}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_vector_rag(%VectorRag{} = vector_rag, attrs) do
    vector_rag
    |> VectorRag.changeset(attrs)
    |> Repo.update()
  end

  def delete_vector_rag(%VectorRag{} = vector_rag) do
    result = Repo.delete(vector_rag)

    if vector_rag.index_path do
      File.rm(vector_rag.index_path)
    end

    result
  end

  def list_vector_rags_with_status do
    list_vector_rags()
    |> Enum.map(&Map.put(&1, :status, vector_rag_status(&1)))
  end

  def vector_rag_status(%VectorRag{enabled: false}), do: :disabled

  def vector_rag_status(%VectorRag{index_path: path, chunk_count: count})
      when is_binary(path) and count > 0 do
    if File.exists?(path), do: :ready, else: :missing_index
  end

  def vector_rag_status(_), do: :empty

  def retrieve_context(query, opts \\ []) when is_binary(query) do
    k = Keyword.get(opts, :k, @default_k)
    rag_name = Keyword.get(opts, :rag_name)

    list_active_vector_rags()
    |> filter_by_rag_name(rag_name)
    |> Enum.flat_map(&query_vector_rag(&1, query, k))
    |> Enum.sort_by(& &1.distance)
    |> Enum.take(k)
  end

  defp filter_by_rag_name(vector_rags, nil), do: vector_rags
  defp filter_by_rag_name(vector_rags, ""), do: vector_rags

  defp filter_by_rag_name(vector_rags, rag_name) when is_binary(rag_name) do
    Enum.filter(vector_rags, &(&1.name == rag_name))
  end

  defp filter_by_rag_name(vector_rags, _rag_name), do: vector_rags

  def build_context_block(query, opts \\ []) do
    case retrieve_context(query, opts) do
      [] ->
        ""

      results ->
        items =
          Enum.map_join(results, "\n", fn result ->
            """
            [#{result.rag_name} ##{result.position + 1}]
            #{result.content}
            """
          end)

        """

        [Vector RAG 참고 지식]
        #{items}
        """
    end
  end

  defp insert_vector_rag(attrs, source, chunk_count) do
    attrs =
      attrs
      |> Map.put("source_filename", source_filename(source))
      |> Map.put("embedding_dim", @embedding_dim)
      |> Map.put("chunk_count", chunk_count)

    %VectorRag{}
    |> VectorRag.changeset(attrs)
    |> Repo.insert()
  end

  defp insert_chunks(vector_rag_id, chunks) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      chunks
      |> Enum.with_index()
      |> Enum.map(fn {content, position} ->
        %{
          id: Ecto.UUID.generate(),
          vector_rag_id: vector_rag_id,
          position: position,
          content: content,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(VectorRagChunk, entries)
    :ok
  end

  defp build_index(vector_rag_id, chunks) do
    vectors = Enum.map(chunks, &embed_text/1)
    max_elements = max(length(vectors), 1)

    with {:ok, index} <- HNSWLib.Index.new(:cosine, @embedding_dim, max_elements),
         :ok <-
           HNSWLib.Index.add_items(index, Nx.tensor(vectors, type: :f32),
             ids: Enum.to_list(0..(length(vectors) - 1))
           ),
         :ok <- File.mkdir_p(index_dir()),
         path = Path.join(index_dir(), "#{vector_rag_id}.hnsw"),
         :ok <- HNSWLib.Index.save_index(index, path) do
      {:ok, path}
    end
  end

  defp query_vector_rag(%VectorRag{} = vector_rag, query, k) do
    with :ready <- vector_rag_status(vector_rag),
         {:ok, index} <-
           HNSWLib.Index.load_index(:cosine, vector_rag.embedding_dim, vector_rag.index_path),
         :ok <- HNSWLib.Index.set_ef(index, max(k * 4, 10)),
         {:ok, labels, distances} <-
           HNSWLib.Index.knn_query(index, Nx.tensor([embed_text(query)], type: :f32),
             k: min(k, vector_rag.chunk_count)
           ) do
      ids = labels |> Nx.to_flat_list() |> Enum.map(&trunc/1)
      dists = distances |> Nx.to_flat_list() |> Enum.map(&(&1 * 1.0))
      chunks = chunks_by_position(vector_rag.id, ids)

      ids
      |> Enum.zip(dists)
      |> Enum.flat_map(&search_result_for_chunk(&1, chunks, vector_rag))
    else
      _ -> []
    end
  end

  defp search_result_for_chunk({position, distance}, chunks, vector_rag) do
    case Map.get(chunks, position) do
      nil ->
        []

      chunk ->
        [
          %{
            rag_id: vector_rag.id,
            rag_name: vector_rag.name,
            position: position,
            distance: distance,
            content: chunk.content
          }
        ]
    end
  end

  defp chunks_by_position(vector_rag_id, positions) do
    from(c in VectorRagChunk,
      where: c.vector_rag_id == ^vector_rag_id and c.position in ^positions
    )
    |> Repo.all()
    |> Map.new(&{&1.position, &1})
  end

  defp read_source(%{path: path} = source) do
    source
    |> source_filename()
    |> read_source_by_extension(path)
  end

  defp read_source(path) when is_binary(path) do
    path
    |> Path.basename()
    |> read_source_by_extension(path)
  end

  defp read_source(_), do: {:error, :invalid_source}

  defp read_source_by_extension(filename, path) do
    case filename |> Path.extname() |> String.downcase() do
      ".pdf" -> extract_pdf_text(path)
      ".docx" -> extract_docx_text(path)
      _ -> File.read(path)
    end
  end

  defp extract_pdf_text(path) do
    case System.find_executable("pdftotext") do
      nil ->
        {:error, :pdftotext_not_found}

      executable ->
        output_path = Path.join(System.tmp_dir!(), "#{Ecto.UUID.generate()}.txt")

        try do
          case System.cmd(executable, ["-layout", "-enc", "UTF-8", path, output_path],
                 stderr_to_stdout: true
               ) do
            {_output, 0} -> File.read(output_path)
            {error, _status} -> {:error, {:pdf_extract_failed, String.trim(error)}}
          end
        after
          File.rm(output_path)
        end
    end
  end

  defp extract_docx_text(path) do
    with {:ok, files} <- :zip.extract(String.to_charlist(path), [:memory]),
         xml_files = docx_xml_files(files),
         false <- Enum.empty?(xml_files) do
      content =
        xml_files
        |> Enum.map(fn {_name, xml} -> extract_docx_xml_text(xml) end)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n\n")

      {:ok, content}
    else
      true -> {:error, :docx_text_not_found}
      {:error, reason} -> {:error, {:docx_extract_failed, reason}}
    end
  end

  defp docx_xml_files(files) do
    files
    |> Enum.filter(fn {name, _content} ->
      name = to_string(name)

      name == "word/document.xml" or
        String.match?(name, ~r/^word\/(header|footer)\d+\.xml$/)
    end)
    |> Enum.sort_by(fn {name, _content} ->
      name = to_string(name)
      if name == "word/document.xml", do: 0, else: 1
    end)
  end

  defp extract_docx_xml_text(xml) do
    xml
    |> to_string()
    |> String.replace(~r/<w:(tab|br|cr)\b[^>]*\/>/, " ")
    |> then(fn content ->
      Regex.scan(~r/<w:t\b[^>]*>(.*?)<\/w:t>/su, content, capture: :all_but_first)
    end)
    |> List.flatten()
    |> Enum.map_join(" ", &decode_xml_entities/1)
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp decode_xml_entities(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> String.replace("&amp;", "&")
  end

  defp source_filename(%{client_name: client_name}), do: client_name
  defp source_filename(path) when is_binary(path), do: Path.basename(path)
  defp source_filename(_), do: nil

  defp chunk_text(content) do
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
      String.slice(text, max(String.length(chunk) - @chunk_overlap, 0), String.length(text)) || ""

    cond do
      chunk == "" -> acc
      String.length(text) <= @chunk_size -> [chunk | acc]
      true -> do_chunk(remaining, [chunk | acc])
    end
  end

  defp embed_text(text) do
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

  defp index_dir do
    Application.get_env(:core, :vector_rag_dir) ||
      Path.join(Application.get_env(:core, :workspace_dir) || "./workspace", "vector_rag")
  end
end
