defmodule LadybugEx.VectorExtensionTest do
  @moduledoc """
  T7 (PRD §6): proves that vector index behavior is unaffected by the list-param
  encoding change, using an explicit two-tier gate so a skip can never
  masquerade as a pass:

    * Excluded by default via `test/test_helper.exs`'s
      `ExUnit.start(exclude: [:vector_extension])`.
    * Every stage below is asserted outright — no `case ... {:error, _} -> :ok`
      permissive fallback. Run explicitly with:

          mix test --only vector_extension

  This must be run on a machine where the vector extension installs (macOS
  ARM, per the PRD) — CI machines without the extension never run this test.
  """

  use ExUnit.Case, async: false
  alias LadybugEx.{Database, Connection, Extensions, Schema, Vector}

  @tag :vector_extension
  test "install, index, insert via list params, and query rank the planted nearest neighbor first" do
    {:ok, db} = Database.in_memory(buffer_pool_size: 1024 * 1024 * 10)
    {:ok, conn} = Connection.new(db)

    assert :ok = Extensions.install_and_load(conn, "vector")

    assert {:ok, :created} =
             Schema.create_node_table(conn, "Doc", [
               {"id", :int64, primary_key: true},
               {"label", :string},
               {"embedding", {:array, :float, 4}}
             ])

    {:ok, stmt} =
      Connection.prepare(conn, "CREATE (:Doc {id: $id, label: $label, embedding: $emb})")

    docs = [
      {1, "target", [1.0, 0.0, 0.0, 0.0]},
      {2, "near", [0.9, 0.1, 0.0, 0.0]},
      {3, "far", [0.0, 0.0, 1.0, 0.0]},
      {4, "farther", [0.0, 1.0, 0.0, 0.0]}
    ]

    for {id, label, emb} <- docs do
      assert {:ok, _} = Connection.execute(conn, stmt, id: id, label: label, emb: emb)
    end

    assert {:ok, _} =
             Vector.create_index(conn, "Doc",
               property: "embedding",
               dimension: 4,
               metric: :cosine
             )

    assert {:ok, results} =
             Vector.query_index(conn, "Doc", "Doc_embedding_idx",
               vector: [1.0, 0.0, 0.0, 0.0],
               k: 4
             )

    assert length(results) == 4
    first = List.first(results)
    assert first["node"]["properties"]["id"] == 1
  end
end
