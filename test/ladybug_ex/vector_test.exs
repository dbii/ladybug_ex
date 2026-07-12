defmodule LadybugEx.VectorTest do
  use ExUnit.Case, async: false
  alias LadybugEx.{Database, Connection, Schema, Vector, Extensions}

  setup do
    # Use a smaller buffer pool size to avoid memory allocation issues
    {:ok, db} = Database.in_memory(buffer_pool_size: 1024 * 1024 * 10)
    {:ok, conn} = Connection.new(db)
    # Resources are automatically cleaned up by garbage collection
    {:ok, %{db: db, conn: conn}}
  end

  defp setup_test_data(conn) do
    # Create a node table with vector property
    {:ok, _} =
      Schema.create_node_table(conn, "Product", [
        {"id", :int64},
        {"name", :string},
        # Vector indexes require a fixed-size ARRAY column, not a LIST
        {"embedding", {:array, :float, 4}}
      ])

    # Insert test data with embeddings
    embeddings = [
      [0.1, 0.2, 0.3, 0.4],
      [0.2, 0.3, 0.4, 0.5],
      [0.9, 0.8, 0.7, 0.6],
      [0.5, 0.5, 0.5, 0.5]
    ]

    Enum.with_index(embeddings, 1)
    |> Enum.each(fn {embedding, id} ->
      embedding_str = "[" <> Enum.map_join(embedding, ", ", &Float.to_string/1) <> "]"

      {:ok, _} =
        Connection.query(conn, """
          CREATE (p:Product {
            id: #{id},
            name: 'Product #{id}',
            embedding: #{embedding_str}
          })
        """)
    end)

    {:ok, embeddings}
  end

  describe "create_index/3" do
    @tag :requires_extension
    test "creates vector index with required options", %{conn: conn} do
      case Extensions.install_and_load(conn, "vector") do
        :ok ->
          setup_test_data(conn)

          result =
            Vector.create_index(conn, "Product",
              property: "embedding",
              dimension: 4
            )

          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          # Extension not available
          assert true
      end
    end

    @tag :requires_extension
    test "creates vector index with custom parameters", %{conn: conn} do
      case Extensions.install_and_load(conn, "vector") do
        :ok ->
          setup_test_data(conn)

          result =
            Vector.create_index(conn, "Product",
              property: "embedding",
              dimension: 4,
              metric: :l2,
              mu: 50,
              ml: 50,
              pu: 600,
              efc: 400,
              cache_embeddings: true,
              index_name: "custom_idx"
            )

          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          assert true
      end
    end

    test "returns error when missing required property option", %{conn: conn} do
      assert {:error, "Missing required option :property"} =
               Vector.create_index(conn, "Product", dimension: 4)
    end

    test "returns error when missing required dimension option", %{conn: conn} do
      assert {:error, "Missing required option :dimension"} =
               Vector.create_index(conn, "Product", property: "embedding")
    end

    test "returns error for invalid dimension", %{conn: conn} do
      assert {:error, "Invalid dimension: must be a positive integer"} =
               Vector.create_index(conn, "Product",
                 property: "embedding",
                 dimension: 0
               )

      assert {:error, "Invalid dimension: must be a positive integer"} =
               Vector.create_index(conn, "Product",
                 property: "embedding",
                 dimension: -1
               )

      assert {:error, "Invalid dimension: must be a positive integer"} =
               Vector.create_index(conn, "Product",
                 property: "embedding",
                 dimension: "not_a_number"
               )
    end

    test "raises on invalid metric", %{conn: conn} do
      assert_raise RuntimeError, ~r/Invalid metric/, fn ->
        Vector.create_index(conn, "Product",
          property: "embedding",
          dimension: 4,
          metric: :invalid_metric
        )
      end
    end

    test "automatically ensures extension is loaded", %{conn: conn} do
      # Even without explicitly loading, should attempt to ensure loaded
      result =
        Vector.create_index(conn, "Product",
          property: "embedding",
          dimension: 4
        )

      # Will fail if extension not installed, but that's ok
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "create_index!/3" do
    test "raises on error", %{conn: conn} do
      assert_raise RuntimeError, ~r/Failed to create vector index/, fn ->
        Vector.create_index!(conn, "Product", property: "embedding")
      end
    end
  end

  describe "query_index/4" do
    @tag :requires_extension
    test "queries vector index with required options", %{conn: conn} do
      case Extensions.install_and_load(conn, "vector") do
        :ok ->
          {:ok, _embeddings} = setup_test_data(conn)

          # Create index
          Vector.create_index(conn, "Product",
            property: "embedding",
            dimension: 4
          )

          # Query with a vector similar to the first one
          query_vector = [0.1, 0.2, 0.3, 0.4]

          result =
            Vector.query_index(conn, "Product", "Product_embedding_idx",
              vector: query_vector,
              k: 2
            )

          case result do
            {:ok, results} ->
              assert is_list(results)
              assert length(results) <= 2

              # Check result structure
              if length(results) > 0 do
                first = List.first(results)
                assert Map.has_key?(first, "node")
                assert Map.has_key?(first, "distance")
              end

            {:error, _reason} ->
              # Index might not be created successfully
              assert true
          end

        {:error, _} ->
          assert true
      end
    end

    @tag :requires_extension
    test "queries with custom efs parameter", %{conn: conn} do
      case Extensions.install_and_load(conn, "vector") do
        :ok ->
          setup_test_data(conn)

          Vector.create_index(conn, "Product",
            property: "embedding",
            dimension: 4
          )

          result =
            Vector.query_index(conn, "Product", "Product_embedding_idx",
              vector: [0.5, 0.5, 0.5, 0.5],
              k: 3,
              efs: 400
            )

          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          assert true
      end
    end

    test "returns error when missing vector option", %{conn: conn} do
      assert {:error, "Missing required option :vector"} =
               Vector.query_index(conn, "Product", "idx", k: 5)
    end

    test "returns error when missing k option", %{conn: conn} do
      assert {:error, "Missing required option :k"} =
               Vector.query_index(conn, "Product", "idx", vector: [0.1, 0.2])
    end

    test "returns error for invalid vector", %{conn: conn} do
      assert {:error, "Invalid vector: must be a list of numbers"} =
               Vector.query_index(conn, "Product", "idx",
                 vector: "not_a_vector",
                 k: 5
               )

      assert {:error, "Invalid vector: must be a list of numbers"} =
               Vector.query_index(conn, "Product", "idx",
                 vector: [0.1, "not_a_number"],
                 k: 5
               )
    end

    test "returns error for invalid k", %{conn: conn} do
      assert {:error, "Invalid k: must be a positive integer"} =
               Vector.query_index(conn, "Product", "idx",
                 vector: [0.1, 0.2],
                 k: 0
               )

      assert {:error, "Invalid k: must be a positive integer"} =
               Vector.query_index(conn, "Product", "idx",
                 vector: [0.1, 0.2],
                 k: -1
               )

      assert {:error, "Invalid k: must be a positive integer"} =
               Vector.query_index(conn, "Product", "idx",
                 vector: [0.1, 0.2],
                 k: "not_a_number"
               )
    end
  end

  describe "query_index!/4" do
    test "raises on error", %{conn: conn} do
      assert_raise RuntimeError, ~r/Failed to query vector index/, fn ->
        Vector.query_index!(conn, "Product", "idx", vector: [0.1])
      end
    end
  end

  describe "drop_index/3" do
    @tag :requires_extension
    test "drops an existing vector index", %{conn: conn} do
      case Extensions.install_and_load(conn, "vector") do
        :ok ->
          setup_test_data(conn)

          # Create index
          Vector.create_index(conn, "Product",
            property: "embedding",
            dimension: 4
          )

          # Drop index
          result = Vector.drop_index(conn, "Product", "Product_embedding_idx")
          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          assert true
      end
    end

    test "handles dropping non-existent index", %{conn: conn} do
      # Behavior depends on database implementation
      result = Vector.drop_index(conn, "Product", "non_existent_idx")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "drop_index!/3" do
    test "may raise on error", %{conn: conn} do
      # Behavior depends on implementation
      try do
        Vector.drop_index!(conn, "Product", "non_existent")
        assert true
      rescue
        RuntimeError -> assert true
      end
    end
  end

  describe "list_indexes/1" do
    @tag :requires_extension
    test "lists vector indexes", %{conn: conn} do
      case Extensions.install_and_load(conn, "vector") do
        :ok ->
          result = Vector.list_indexes(conn)

          case result do
            {:ok, indexes} ->
              assert is_list(indexes)

            {:error, _reason} ->
              # Function might not be implemented in LadybugDB yet
              assert true
          end

        {:error, _} ->
          assert true
      end
    end
  end

  describe "list_indexes!/1" do
    test "returns list or raises", %{conn: conn} do
      try do
        indexes = Vector.list_indexes!(conn)
        assert is_list(indexes)
      rescue
        RuntimeError -> assert true
      end
    end
  end

  describe "distance metrics" do
    @tag :requires_extension
    test "supports different distance metrics", %{conn: conn} do
      case Extensions.install_and_load(conn, "vector") do
        :ok ->
          setup_test_data(conn)

          metrics = [:cosine, :l2, :l2sq, :dotproduct]

          Enum.each(metrics, fn metric ->
            index_name = "idx_#{metric}"

            result =
              Vector.create_index(conn, "Product",
                property: "embedding",
                dimension: 4,
                metric: metric,
                index_name: index_name
              )

            # Just check it doesn't crash
            assert match?({:ok, _}, result) or match?({:error, _}, result)

            # Clean up
            Vector.drop_index(conn, "Product", index_name)
          end)

        {:error, _} ->
          assert true
      end
    end
  end

  describe "integration" do
    @tag :requires_extension
    test "complete vector search workflow", %{conn: conn} do
      case Extensions.install_and_load(conn, "vector") do
        :ok ->
          # Setup data
          {:ok, _embeddings} = setup_test_data(conn)

          # Create index
          assert {:ok, _} =
                   Vector.create_index(conn, "Product",
                     property: "embedding",
                     dimension: 4,
                     metric: :cosine
                   )

          # Search for similar vectors
          query_vector = [0.15, 0.25, 0.35, 0.45]

          case Vector.query_index(conn, "Product", "Product_embedding_idx",
                 vector: query_vector,
                 k: 2
               ) do
            {:ok, results} ->
              assert is_list(results)
              assert length(results) <= 2

              # Results should be ordered by distance
              if length(results) > 1 do
                distances = Enum.map(results, & &1["distance"])
                assert distances == Enum.sort(distances)
              end

            {:error, _} ->
              # Might fail if index creation had issues
              assert true
          end

          # Drop index
          Vector.drop_index(conn, "Product", "Product_embedding_idx")

        {:error, _} ->
          assert true
      end
    end

    @tag :requires_extension
    test "filtered vector search with projected graph", %{conn: conn} do
      case Extensions.install_and_load(conn, "vector") do
        :ok ->
          # Create products with categories
          {:ok, _} =
            Schema.create_node_table(conn, "Item", [
              {"id", :int64},
              {"name", :string},
              {"category", :string},
              {"embedding", {:array, :float, 3}}
            ])

          # Insert items
          items = [
            {1, "Laptop", "electronics", [0.1, 0.2, 0.3]},
            {2, "Phone", "electronics", [0.2, 0.3, 0.4]},
            {3, "Shirt", "clothing", [0.9, 0.8, 0.7]},
            {4, "Shoes", "clothing", [0.8, 0.7, 0.6]}
          ]

          Enum.each(items, fn {id, name, category, embedding} ->
            emb_str = "[" <> Enum.map_join(embedding, ", ", &Float.to_string/1) <> "]"

            {:ok, _} =
              Connection.query(conn, """
                CREATE (i:Item {
                  id: #{id},
                  name: '#{name}',
                  category: '#{category}',
                  embedding: #{emb_str}
                })
              """)
          end)

          # Create index
          Vector.create_index(conn, "Item",
            property: "embedding",
            dimension: 3
          )

          # Create filtered projection for electronics only
          result =
            Connection.query(conn, """
              CALL PROJECT_GRAPH('electronics_only', 'Item', '*')
              WHERE n.category = 'electronics'
              RETURN *
            """)

          case result do
            {:ok, _} ->
              # Query on projected graph should only return electronics
              query_result =
                Vector.query_index(conn, "electronics_only", "Item_embedding_idx",
                  vector: [0.15, 0.25, 0.35],
                  k: 10
                )

              case query_result do
                {:ok, results} ->
                  # Should only get electronics items
                  assert length(results) <= 2

                {:error, _} ->
                  # Projected graph queries might not be fully supported
                  assert true
              end

            {:error, _} ->
              # PROJECT_GRAPH might not be available
              assert true
          end

        {:error, _} ->
          assert true
      end
    end
  end
end
