defmodule Core.Contexts.VectorRagsTest do
  use Core.DataCase, async: false

  alias Core.Contexts.VectorRags
  alias Core.Agent.Tools.VectorRagSearch
  import Core.Fixtures

  test "lexical retrieval cites source and excludes another user's documents" do
    alice = user_fixture()
    bob = user_fixture()
    path = Path.join(System.tmp_dir!(), "rag_#{System.unique_integer([:positive])}.txt")
    File.write!(path, "Phoenix LiveView는 서버에서 UI 상태를 관리합니다.")

    previous = Application.get_env(:core, :azure_openai_embedding_deployment)
    Application.delete_env(:core, :azure_openai_embedding_deployment)

    on_exit(fn ->
      Application.put_env(:core, :azure_openai_embedding_deployment, previous)
      File.rm(path)
    end)

    assert {:ok, rag} =
             VectorRags.create_vector_rag(
               %{name: "Phoenix guide"},
               %{path: path, client_name: "guide.txt"},
               alice.id
             )

    assert rag.embedding_model == "lexical"
    assert rag.index_path == nil
    assert VectorRags.vector_rag_status(rag) == :ready

    assert [%{source_filename: "guide.txt", content: content, score: score}] =
             VectorRags.retrieve_context(alice.id, "LiveView")

    assert String.contains?(content, "LiveView")
    assert score > 0
    assert [] == VectorRags.retrieve_context(bob.id, "LiveView")

    assert {:ok, %{results: [%{source_filename: "guide.txt"}]}} =
             VectorRagSearch.execute("search_vector_rag", %{"query" => "LiveView"}, alice.id)

    assert {:error, :invalid_query_or_user} =
             VectorRagSearch.execute("search_vector_rag", %{"query" => "LiveView"}, nil)

    assert {:ok, _} = VectorRags.delete_vector_rag(alice.id, rag)
  end
end
