defmodule LadybugEx do
  @moduledoc """
  LadybugEx - Elixir bindings for LadybugDB embedded graph database.

  LadybugDB is a high-performance embedded property graph database that supports
  the Cypher query language. This library provides idiomatic Elixir bindings
  for working with LadybugDB databases.

  ## Features

    * Full Cypher query language support
    * Property graph data model (nodes and relationships with properties)
    * Thread-safe connections for concurrent operations
    * Prepared statements for efficient repeated queries
    * Transaction support
    * Extensible architecture with official extensions:
      * Vector search via HNSW indexing
      * Full-text search with BM25 ranking
      * LLM embeddings generation
      * And many more (algo, azure, delta, duckdb, etc.)
    * In-memory and persistent database modes

  ## Quick Start

  ### Creating a Database

      # Persistent database
      {:ok, db} = LadybugEx.Database.open("/path/to/database")

      # In-memory database (great for testing)
      {:ok, db} = LadybugEx.Database.in_memory()

  ### Establishing a Connection

      {:ok, conn} = LadybugEx.Connection.new(db)

  ### Creating Schema

      alias LadybugEx.{Connection, Schema}

      # Create node table
      Schema.create_node_table(conn, "Person", [
        {:id, :int64, primary_key: true},
        {:name, :string},
        {:age, :int64}
      ])

      # Create relationship table
      Schema.create_rel_table(conn, "KNOWS", "Person", "Person", [
        {:since, :date}
      ])

  ### Working with Graphs

  #### Using Cypher Queries

      # Create nodes
      Connection.query!(conn, \"\"\"
        CREATE (:Person {id: 1, name: 'Alice', age: 30})
      \"\"\")

      # Query nodes
      results = Connection.query!(conn, \"\"\"
        MATCH (p:Person)
        WHERE p.age > 25
        RETURN p.name AS name, p.age AS age
      \"\"\")

  #### Using the Graph Module

      alias LadybugEx.Graph

      # Create a node
      {:ok, node} = Graph.create_node(conn, "Person",
        name: "Bob",
        age: 25
      )

      # Find nodes
      {:ok, people} = Graph.find_nodes(conn, "Person", %{age: 25})

      # Create relationships
      {:ok, rel} = Graph.create_relationship(conn,
        node1_id, node2_id, "KNOWS",
        since: ~D[2020-01-01]
      )

      # Find shortest path
      {:ok, path} = Graph.shortest_path(conn, alice_id, bob_id)

  ### Extensions

  #### Vector Search

      alias LadybugEx.{Extensions, Vector}

      # Install and load the vector extension
      Extensions.install_and_load!(conn, "vector")

      # Create a vector index
      Vector.create_index!(conn, "Document",
        property: "embedding",
        dimension: 1536,
        metric: :cosine
      )

      # Perform similarity search
      query_vector = [0.1, 0.2, 0.3, ...]  # Your embedding
      {:ok, results} = Vector.query_index(conn, "Document", "Document_embedding_idx",
        vector: query_vector,
        k: 10
      )

  #### Full-Text Search

      alias LadybugEx.{Extensions, FTS}

      # Install and load the FTS extension
      Extensions.install_and_load!(conn, "fts")

      # Create a full-text search index
      FTS.create_index!(conn, "Article",
        properties: ["title", "content"],
        stemmer: :english
      )

      # Search documents
      {:ok, results} = FTS.query_index(conn, "Article", "Article_fts_title_content_idx",
        query: "machine learning",
        limit: 20
      )

  #### LLM Embeddings

      alias LadybugEx.{Extensions, LLM}

      # Install and load the LLM extension
      Extensions.install_and_load!(conn, "llm")

      # Generate embeddings (requires API keys in env vars)
      {:ok, embedding} = LLM.create_embedding(conn,
        "This is my text to embed",
        provider: :openai,
        model: "text-embedding-ada-002"
      )

  ### Prepared Statements

      # Prepare a statement
      {:ok, stmt} = Connection.prepare(conn, \"\"\"
        CREATE (:Person {id: $id, name: $name, age: $age})
      \"\"\")

      # Execute with different parameters
      Connection.execute!(conn, stmt, id: 2, name: "Charlie", age: 35)
      Connection.execute!(conn, stmt, id: 3, name: "Diana", age: 28)

  ### Transactions

      Connection.transaction(conn, fn conn ->
        with {:ok, _} <- Connection.query(conn, "CREATE (:Person {name: 'Eve'})"),
             {:ok, _} <- Connection.query(conn, "CREATE (:Person {name: 'Frank'})") do
          {:ok, :success}
        end
      end)

  ## Modules

    * `LadybugEx.Database` - Database management
    * `LadybugEx.Connection` - Connection and query execution
    * `LadybugEx.Graph` - High-level graph operations
    * `LadybugEx.Schema` - Schema management
    * `LadybugEx.PreparedStatement` - Prepared statement support

  ### Extension Modules

    * `LadybugEx.Extensions` - Generic extension management
    * `LadybugEx.Vector` - Vector similarity search (requires vector extension)
    * `LadybugEx.FTS` - Full-text search with BM25 (requires fts extension)
    * `LadybugEx.LLM` - LLM embeddings generation (requires llm extension)

  ## Configuration

  Database configuration options can be passed when opening:

      LadybugEx.Database.open("/path/to/db",
        buffer_pool_size: 1024 * 1024 * 256,  # 256MB
        max_num_threads: 8,
        enable_compression: true
      )

  ## Performance Tips

    1. Use prepared statements for repeated queries
    2. Create indexes on frequently queried properties
    3. Use connection pooling for concurrent operations
    4. Batch operations within transactions when possible
    5. Configure appropriate buffer pool size for your workload

  """

  @doc """
  Returns the version of the LadybugEx library.
  """
  def version, do: "0.1.0"

  @doc """
  Returns :world for testing purposes.
  """
  def hello, do: :world
end
