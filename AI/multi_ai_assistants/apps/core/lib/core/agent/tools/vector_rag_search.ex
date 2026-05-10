defmodule Core.Agent.Tools.VectorRagSearch do
  @moduledoc """
  활성 Vector RAG 지식베이스에서 관련 청크를 검색하는 도구.
  """

  @behaviour Core.Agent.Tool

  alias Core.Contexts.VectorRags

  def definition("search_vector_rag") do
    knowledge_names =
      VectorRags.list_active_vector_rags()
      |> Enum.map(& &1.name)

    knowledge_hint =
      case knowledge_names do
        [] -> "No Vector RAG knowledge bases are currently available."
        names -> "Available Vector RAG knowledge bases: #{Enum.join(names, ", ")}."
      end

    %{
      name: "search_vector_rag",
      description:
        "Search the local Vector RAG knowledge bases for relevant internal/contextual knowledge. #{knowledge_hint} Use this before answering when the task may relate to an available knowledge base.",
      parameters: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description: "Search query to retrieve relevant knowledge chunks."
          },
          knowledge_name: %{
            type: "string",
            description:
              "Optional exact Vector RAG knowledge base name to search, for example '에이전트2리더'. Leave empty to search all active knowledge bases."
          },
          k: %{
            type: "integer",
            description: "Maximum number of chunks to return. Defaults to 4."
          }
        },
        required: ["query"]
      }
    }
  end

  def definition(_), do: nil

  def execute("search_vector_rag", %{"query" => query} = arguments) when is_binary(query) do
    k = normalize_k(Map.get(arguments, "k"))
    knowledge_name = Map.get(arguments, "knowledge_name") || Map.get(arguments, "rag_name")

    results = VectorRags.retrieve_context(query, k: k, rag_name: knowledge_name)

    {:ok,
     %{
       query: query,
       knowledge_name: empty_to_nil(knowledge_name),
       result_count: length(results),
       results:
         Enum.map(results, fn result ->
           %{
             knowledge_name: result.rag_name,
             chunk: result.position + 1,
             distance: result.distance,
             content: result.content
           }
         end)
     }}
  end

  def execute("search_vector_rag", _arguments), do: {:error, "query is required"}

  defp normalize_k(k) when is_integer(k), do: k |> max(1) |> min(10)

  defp normalize_k(k) when is_binary(k) do
    case Integer.parse(k) do
      {value, _} -> normalize_k(value)
      :error -> 4
    end
  end

  defp normalize_k(_), do: 4

  defp empty_to_nil(value) when value in ["", nil], do: nil
  defp empty_to_nil(value), do: value
end
