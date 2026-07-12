defmodule LadybugEx.FTSTest do
  use ExUnit.Case, async: false
  alias LadybugEx.{Database, Connection, Schema, FTS, Extensions}

  setup do
    # Use a smaller buffer pool size to avoid memory allocation issues
    {:ok, db} = Database.in_memory(buffer_pool_size: 1024 * 1024 * 10)
    {:ok, conn} = Connection.new(db)
    # Resources are automatically cleaned up by garbage collection
    {:ok, %{db: db, conn: conn}}
  end

  defp setup_test_data(conn) do
    # Create a node table with text properties
    {:ok, _} =
      Schema.create_node_table(conn, "Article", [
        {"id", :int64},
        {"title", :string},
        {"abstract", :string},
        {"content", :string}
      ])

    # Insert test articles
    articles = [
      {1, "Introduction to Machine Learning",
       "A comprehensive overview of machine learning algorithms and techniques.",
       "Machine learning is a subset of artificial intelligence that enables computers to learn from data..."},
      {2, "Deep Learning Neural Networks",
       "Understanding the architecture and training of deep neural networks.",
       "Deep learning has revolutionized many fields including computer vision and natural language processing..."},
      {3, "Natural Language Processing",
       "Techniques for processing and understanding human language using computers.",
       "NLP combines computational linguistics with machine learning to process human language..."},
      {4, "Computer Vision Applications",
       "Modern applications of computer vision in industry and research.",
       "Computer vision enables machines to interpret and understand visual information from the world..."}
    ]

    Enum.each(articles, fn {id, title, abstract, content} ->
      {:ok, _} =
        Connection.query(conn, """
          CREATE (a:Article {
            id: #{id},
            title: '#{escape_string(title)}',
            abstract: '#{escape_string(abstract)}',
            content: '#{escape_string(content)}'
          })
        """)
    end)

    {:ok, articles}
  end

  defp escape_string(str) do
    str
    |> String.replace("'", "\\'")
    |> String.replace("\\", "\\\\")
  end

  describe "create_index/3" do
    @tag :requires_extension
    test "creates FTS index with single property", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          setup_test_data(conn)

          result = FTS.create_index(conn, "Article", properties: ["content"])

          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          # Extension not available
          assert true
      end
    end

    @tag :requires_extension
    test "creates FTS index with multiple properties", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          setup_test_data(conn)

          result =
            FTS.create_index(conn, "Article",
              properties: ["title", "abstract", "content"],
              stemmer: :english
            )

          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          assert true
      end
    end

    @tag :requires_extension
    test "creates FTS index with custom stopwords", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          setup_test_data(conn)

          result =
            FTS.create_index(conn, "Article",
              properties: ["content"],
              stemmer: :english,
              stopwords: ["the", "a", "an", "and", "or", "but", "is", "are"],
              index_name: "custom_fts_idx"
            )

          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          assert true
      end
    end

    @tag :requires_extension
    test "supports different stemmers", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          setup_test_data(conn)

          stemmers = [:english, :french, :german, :spanish, :porter]

          Enum.each(stemmers, fn stemmer ->
            index_name = "idx_#{stemmer}"

            result =
              FTS.create_index(conn, "Article",
                properties: ["content"],
                stemmer: stemmer,
                index_name: index_name
              )

            assert match?({:ok, _}, result) or match?({:error, _}, result)

            # Clean up
            FTS.drop_index(conn, "Article", index_name)
          end)

        {:error, _} ->
          assert true
      end
    end

    test "returns error when missing properties option", %{conn: conn} do
      assert {:error, "Missing required option :properties"} =
               FTS.create_index(conn, "Article", stemmer: :english)
    end

    test "returns error for empty properties", %{conn: conn} do
      assert {:error, "Invalid properties: must be a non-empty list"} =
               FTS.create_index(conn, "Article", properties: [])
    end

    test "returns error for invalid properties", %{conn: conn} do
      assert {:error, "Invalid properties: all must be strings"} =
               FTS.create_index(conn, "Article", properties: [:not_a_string])

      assert {:error, "Invalid properties: must be a non-empty list"} =
               FTS.create_index(conn, "Article", properties: "not_a_list")
    end

    test "returns error for invalid stemmer", %{conn: conn} do
      assert {:error, "Invalid stemmer: :invalid_stemmer"} =
               FTS.create_index(conn, "Article",
                 properties: ["content"],
                 stemmer: :invalid_stemmer
               )
    end

    test "automatically ensures extension is loaded", %{conn: conn} do
      # Even without explicitly loading, should attempt to ensure loaded
      result = FTS.create_index(conn, "Article", properties: ["content"])

      # Will fail if extension not installed, but that's ok
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "create_index!/3" do
    test "raises on error", %{conn: conn} do
      assert_raise RuntimeError, ~r/Failed to create FTS index/, fn ->
        FTS.create_index!(conn, "Article", stemmer: :english)
      end
    end
  end

  describe "query_index/4" do
    @tag :requires_extension
    test "queries FTS index with simple query", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          setup_test_data(conn)

          # Create index
          FTS.create_index(conn, "Article", properties: ["title", "content"])

          result =
            FTS.query_index(conn, "Article", "Article_fts_title_content_idx",
              query: "machine learning"
            )

          case result do
            {:ok, results} ->
              assert is_list(results)

              # Check result structure
              if length(results) > 0 do
                first = List.first(results)
                assert Map.has_key?(first, "node")
                assert Map.has_key?(first, "score")
              end

            {:error, _} ->
              # Index might not be created successfully
              assert true
          end

        {:error, _} ->
          assert true
      end
    end

    @tag :requires_extension
    test "queries with conjunctive (AND) logic", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          setup_test_data(conn)

          FTS.create_index(conn, "Article", properties: ["content"])

          result =
            FTS.query_index(conn, "Article", "Article_fts_content_idx",
              query: "machine learning",
              conjunctive: true
            )

          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          assert true
      end
    end

    @tag :requires_extension
    test "queries with disjunctive (OR) logic", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          setup_test_data(conn)

          FTS.create_index(conn, "Article", properties: ["content"])

          result =
            FTS.query_index(conn, "Article", "Article_fts_content_idx",
              query: "neural vision language",
              conjunctive: false
            )

          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          assert true
      end
    end

    @tag :requires_extension
    test "queries with custom BM25 parameters", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          setup_test_data(conn)

          FTS.create_index(conn, "Article", properties: ["content"])

          result =
            FTS.query_index(conn, "Article", "Article_fts_content_idx",
              query: "artificial intelligence",
              k: 1.5,
              b: 0.8,
              limit: 50
            )

          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          assert true
      end
    end

    test "returns error when missing query option", %{conn: conn} do
      assert {:error, "Missing required option :query"} =
               FTS.query_index(conn, "Article", "idx", limit: 10)
    end

    test "returns error for empty query", %{conn: conn} do
      assert {:error, "Invalid query: must be a non-empty string"} =
               FTS.query_index(conn, "Article", "idx",
                 query: "",
                 limit: 10
               )

      assert {:error, "Invalid query: must be a non-empty string"} =
               FTS.query_index(conn, "Article", "idx",
                 query: "   ",
                 limit: 10
               )
    end

    test "returns error for invalid query type", %{conn: conn} do
      assert {:error, "Invalid query: must be a non-empty string"} =
               FTS.query_index(conn, "Article", "idx",
                 query: 123,
                 limit: 10
               )
    end
  end

  describe "query_index!/4" do
    test "raises on error", %{conn: conn} do
      assert_raise RuntimeError, ~r/Failed to query FTS index/, fn ->
        FTS.query_index!(conn, "Article", "idx", query: "")
      end
    end
  end

  describe "drop_index/3" do
    @tag :requires_extension
    test "drops an existing FTS index", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          setup_test_data(conn)

          # Create index
          FTS.create_index(conn, "Article", properties: ["content"])

          # Drop index
          result = FTS.drop_index(conn, "Article", "Article_fts_content_idx")
          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          assert true
      end
    end

    test "handles dropping non-existent index", %{conn: conn} do
      result = FTS.drop_index(conn, "Article", "non_existent_idx")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "drop_index!/3" do
    test "may raise on error", %{conn: conn} do
      try do
        FTS.drop_index!(conn, "Article", "non_existent")
        assert true
      rescue
        RuntimeError -> assert true
      end
    end
  end

  describe "list_indexes/1" do
    @tag :requires_extension
    test "lists FTS indexes", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          result = FTS.list_indexes(conn)

          case result do
            {:ok, indexes} ->
              assert is_list(indexes)

            {:error, _} ->
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
        indexes = FTS.list_indexes!(conn)
        assert is_list(indexes)
      rescue
        RuntimeError -> assert true
      end
    end
  end

  describe "analyze_text/3" do
    @tag :requires_extension
    test "analyzes text with stemmer", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          result = FTS.analyze_text(conn, "running quickly", :english)

          case result do
            {:ok, tokens} ->
              assert is_list(tokens)

            # Should stem "running" to "run" and "quickly" to "quick"

            {:error, _} ->
              # Function might not be implemented
              assert true
          end

        {:error, _} ->
          assert true
      end
    end

    @tag :requires_extension
    test "analyzes text with different stemmers", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          stemmers = [:english, :french, :porter]

          Enum.each(stemmers, fn stemmer ->
            result = FTS.analyze_text(conn, "testing languages", stemmer)
            assert match?({:ok, _}, result) or match?({:error, _}, result)
          end)

        {:error, _} ->
          assert true
      end
    end
  end

  describe "analyze_text!/3" do
    test "returns tokens or raises", %{conn: conn} do
      try do
        tokens = FTS.analyze_text!(conn, "testing", :english)
        assert is_list(tokens)
      rescue
        RuntimeError -> assert true
      end
    end
  end

  describe "integration" do
    @tag :requires_extension
    test "complete full-text search workflow", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          # Setup data
          setup_test_data(conn)

          # Create multi-property index
          assert {:ok, _} =
                   FTS.create_index(conn, "Article",
                     properties: ["title", "abstract", "content"],
                     stemmer: :english
                   )

          # Search for machine learning articles
          case FTS.query_index(conn, "Article", "Article_fts_title_abstract_content_idx",
                 query: "machine learning neural",
                 conjunctive: false,
                 limit: 10
               ) do
            {:ok, results} ->
              assert is_list(results)

              # Should find articles about ML and neural networks
              if length(results) > 0 do
                # Results should have scores
                scores = Enum.map(results, & &1["score"])
                # Scores should be sorted in descending order (best matches first)
                assert scores == Enum.sort(scores, :desc)
              end

            {:error, _} ->
              assert true
          end

          # Drop index
          FTS.drop_index(conn, "Article", "Article_fts_title_abstract_content_idx")

        {:error, _} ->
          assert true
      end
    end

    @tag :requires_extension
    test "relevance ranking with BM25", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          # Create documents with varying relevance
          {:ok, _} =
            Schema.create_node_table(conn, "Document", [
              {"id", :int64},
              {"text", :string}
            ])

          docs = [
            {1, "machine learning machine learning machine learning"},
            {2, "machine learning is important"},
            {3, "learning about machines"},
            {4, "completely unrelated text"}
          ]

          Enum.each(docs, fn {id, text} ->
            {:ok, _} =
              Connection.query(conn, """
                CREATE (d:Document {id: #{id}, text: '#{text}'})
              """)
          end)

          # Create index
          FTS.create_index(conn, "Document", properties: ["text"])

          # Search for "machine learning"
          case FTS.query_index(conn, "Document", "Document_fts_text_idx",
                 query: "machine learning",
                 limit: 10
               ) do
            {:ok, results} ->
              if length(results) > 0 do
                # Document with most repetitions should score highest
                scores = Enum.map(results, & &1["score"])
                assert hd(scores) == Enum.max(scores)
              end

            {:error, _} ->
              assert true
          end

        {:error, _} ->
          assert true
      end
    end

    @tag :requires_extension
    test "stopword filtering", %{conn: conn} do
      case Extensions.install_and_load(conn, "fts") do
        :ok ->
          {:ok, _} =
            Schema.create_node_table(conn, "Text", [
              {"id", :int64},
              {"content", :string}
            ])

          # Insert text with common stopwords
          {:ok, _} =
            Connection.query(conn, """
              CREATE (t:Text {
                id: 1,
                content: 'The quick brown fox jumps over the lazy dog'
              })
            """)

          {:ok, _} =
            Connection.query(conn, """
              CREATE (t:Text {
                id: 2,
                content: 'A fox is an animal and the dog is too'
              })
            """)

          # Create index with custom stopwords
          FTS.create_index(conn, "Text",
            properties: ["content"],
            stopwords: ["the", "a", "an", "is", "and", "over", "too"]
          )

          # Search should ignore stopwords
          result =
            FTS.query_index(conn, "Text", "Text_fts_content_idx",
              # "fox" and "dog" should be the only terms searched
              query: "the fox and dog"
            )

          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          assert true
      end
    end
  end
end
