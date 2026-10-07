defmodule Core.VectorIndexTest do
  use ExUnit.Case, async: true

  test "native vector index persists and queries Nx tensors" do
    path = Path.join(System.tmp_dir!(), "hnsw_#{System.unique_integer([:positive])}.index")
    on_exit(fn -> File.rm(path) end)

    vectors = Nx.tensor([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]], type: :f32)

    assert {:ok, index} = HNSWLib.Index.new(:cosine, 3, 2)
    assert :ok = HNSWLib.Index.add_items(index, vectors, ids: [10, 20])
    assert :ok = HNSWLib.Index.save_index(index, path)
    assert {:ok, restored} = HNSWLib.Index.load_index(:cosine, 3, path)
    assert :ok = HNSWLib.Index.set_ef(restored, 10)

    assert {:ok, labels, distances} =
             HNSWLib.Index.knn_query(restored, Nx.tensor([[1.0, 0.0, 0.0]], type: :f32), k: 2)

    assert Nx.to_flat_list(labels) == [10, 20]
    assert [nearest, other] = Nx.to_flat_list(distances)
    assert_in_delta nearest, 0.0, 1.0e-6
    assert_in_delta other, 1.0, 1.0e-6
  end
end
