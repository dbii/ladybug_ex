# LadybugEx

[![Hex.pm](https://img.shields.io/hexpm/v/ladybug_ex.svg)](https://hex.pm/packages/ladybug_ex)
[![Hex Docs](https://img.shields.io/badge/hex-docs-purple.svg)](https://hexdocs.pm/ladybug_ex)
[![GitHub](https://img.shields.io/github/stars/tylerdavis/ladybug_ex?style=social)](https://github.com/tylerdavis/ladybug_ex)
[![Elixir CI](https://github.com/tylerdavis/ladybug_ex/actions/workflows/elixir.yml/badge.svg)](https://github.com/tylerdavis/ladybug_ex/actions)

Elixir bindings for LadybugDB - a high-performance embedded property graph database with Cypher query support. A great option for building fast, low-ops agentic systems.

> A note on AI slop. This project was generated using Claude Code, with some careful babysitting. It is fully tested both with unit testing and manual QA, so we should be in good shape. With all of that said, this is a new project that will likely have areas that need improvement.

**[Hex Package](https://hex.pm/packages/ladybug_ex)** | **[Documentation](https://hexdocs.pm/ladybug_ex)** | **[GitHub](https://github.com/tylerdavis/ladybug_ex)**

## Features

- 🚀 **High Performance**: Built on LadybugDB's optimized C++ engine
- 📊 **Property Graph Model**: Full support for nodes, relationships, and properties
- 🔍 **Cypher Query Language**: Industry-standard graph query language
- 🔄 **Thread-Safe**: Concurrent operations with multiple connections
- 💾 **Flexible Storage**: Both persistent and in-memory database modes
- 🎯 **Prepared Statements**: Efficient repeated query execution
- 🔐 **Transactions**: ACID compliance with transaction support
- 🔮 **Vector Search**: HNSW-based similarity search for embeddings

## Installation

Add `ladybug_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ladybug_ex, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Requirements

- Elixir ~> 1.19
- Rust (latest stable version)
- C++ compiler (for building LadybugDB)

The LadybugDB C++ library will be automatically compiled during the build process.

## Quick Start

### Basic Usage

```elixir
# Create an in-memory database
{:ok, db} = LadybugEx.Database.in_memory()

# Create a connection
{:ok, conn} = LadybugEx.Connection.new(db)

# Create schema
LadybugEx.Schema.create_node_table(conn, "Person", [
  {:id, :int64, primary_key: true},
  {:name, :string},
  {:age, :int64}
])

# Insert data using Cypher
LadybugEx.Connection.query!(conn, """
  CREATE (:Person {id: 1, name: 'Alice', age: 30})
""")

# Query data
results = LadybugEx.Connection.query!(conn, """
  MATCH (p:Person)
  WHERE p.age >= 30
  RETURN p.name AS name, p.age AS age
""")
# => [%{name: "Alice", age: 30}]
```

### Using the Graph Module

```elixir
alias LadybugEx.Graph

# Create nodes
{:ok, alice} = Graph.create_node(conn, "Person",
  name: "Alice",
  age: 30
)

{:ok, bob} = Graph.create_node(conn, "Person",
  name: "Bob",
  age: 25
)

# Create relationships
{:ok, rel} = Graph.create_relationship(conn,
  alice.id, bob.id, "KNOWS",
  since: 2020
)

# Find nodes
{:ok, people} = Graph.find_nodes(conn, "Person", %{age: 25})

# Find shortest path
{:ok, path} = Graph.shortest_path(conn, alice.id, bob.id)
```

### Prepared Statements

```elixir
# Prepare once
{:ok, stmt} = LadybugEx.Connection.prepare(conn, """
  CREATE (:Person {id: $id, name: $name, age: $age})
""")

# Execute multiple times
LadybugEx.Connection.execute!(conn, stmt,
  id: 2,
  name: "Charlie",
  age: 35
)

LadybugEx.Connection.execute!(conn, stmt,
  id: 3,
  name: "Diana",
  age: 28
)
```

### Transactions

```elixir
LadybugEx.Connection.transaction(conn, fn conn ->
  with {:ok, _} <- Graph.create_node(conn, "Account", balance: 1000),
       {:ok, _} <- Graph.create_node(conn, "Account", balance: 500) do
    {:ok, :success}
  end
end)
```

## Vector Search

LadybugEx provides support for LadybugDB's built-in vector extension, enabling high-performance similarity search over embeddings using HNSW (Hierarchical Navigable Small World) indexing.

### Setup

The vector extension is included with LadybugDB but must be installed and loaded before use:

```elixir
# Install and load the vector extension
case LadybugEx.Vector.install_and_load(conn) do
  {:ok, :loaded} ->
    IO.puts("Vector extension loaded successfully")
  {:error, reason} ->
    IO.puts("Could not load vector extension: #{reason}")
end
```

### Creating Tables with Vectors

```elixir
# Create a table with vector column
LadybugEx.Schema.create_node_table(conn, "Document", [
  {:id, :int64, primary_key: true},
  {:title, :string},
  {:content, :string},
  {:embedding, {:array, :float, 1536}}  # Fixed-size FLOAT array (required for vector indexes)
  # Or use {:array, :double, 1536} for 64-bit precision
])
```

### Creating Vector Indexes

```elixir
# Create an HNSW index for fast similarity search
{:ok, _} = LadybugEx.Vector.create_index(conn, "Document",
  property: "embedding",           # Column containing the vectors
  dimension: 1536,                 # Vector dimension
  index_name: "doc_embedding_idx", # Optional (default: auto-generated)
  metric: :cosine,                 # Distance metric: :cosine, :l2, :l2sq, :dotproduct
  mu: 30,                          # Max degree in upper graph
  ml: 30,                          # Max degree in lower graph
  pu: 0.05,                        # Percentage of nodes in upper graph (0.0-1.0)
  efc: 200,                        # Candidates during construction
  cache_embeddings: true           # Cache during index build
)
```

### Inserting Vector Data

```elixir
# Insert documents with embeddings
LadybugEx.Connection.query!(conn, """
  CREATE (:Document {
    id: 1,
    title: 'Introduction to Graph Databases',
    content: 'Graph databases are...',
    embedding: [0.1, 0.2, 0.3, ...]  # Your embedding vector
  })
""")
```

### Vector Similarity Search

```elixir
# Find k nearest neighbors
query_embedding = [0.1, 0.15, 0.25, ...]  # Query vector

{:ok, results} = LadybugEx.Vector.query_index(conn, "Document", "doc_embedding_idx",
  vector: query_embedding,  # Query vector
  k: 10,                    # Number of results
  efs: 200                  # Search candidates (higher = more accurate but slower)
)

# Results include the node and distance
Enum.each(results, fn %{"node" => node, "distance" => distance} ->
  IO.puts("#{node["title"]} - Distance: #{distance}")
end)
```

### Combining Vector Search with Graph Traversal

```elixir
# Find similar documents and their authors
results = LadybugEx.Connection.query!(conn, """
  CALL QUERY_VECTOR_INDEX('Document', 'doc_embedding_idx', $vec, 5)
  WITH node AS d, distance
  MATCH (a:Author)-[:WROTE]->(d)
  RETURN d.title AS title, a.name AS author, distance
  ORDER BY distance
""", vec: query_embedding)
```

### Distance Metrics

- **`:cosine`** - Cosine similarity (best for normalized embeddings)
- **`:l2`** - Euclidean distance
- **`:l2sq`** - Squared Euclidean distance
- **`:dotproduct`** - Dot product similarity

### Managing Vector Indexes

```elixir
# Drop a vector index
{:ok, :dropped} = LadybugEx.Vector.drop_index(conn, "Document", "doc_embedding_idx")

# List all indexes (including vector indexes)
{:ok, results} = LadybugEx.Connection.query(conn, "CALL SHOW_INDEXES() RETURN *;")
```

## Extension Management

LadybugDB supports various extensions to add additional functionality. The `LadybugEx.Extensions` module provides a unified interface for managing all LadybugDB extensions.

### Available Extensions

- `:algo` - Graph algorithms
- `:azure` - Azure Blob Storage and ADLS scanning
- `:delta` - Delta Lake table scanning
- `:duckdb` - DuckDB database integration
- `:fts` - Full-text search using BM25
- `:httpfs` - HTTP(S) file operations (currently broken: the prebuilt binary is ABI-incompatible with the bundled engine and crashes the VM on load)
- `:iceberg` - Iceberg table scanning
- `:json` - JSON data manipulation
- `:llm` - Text embeddings via external APIs
- `:neo4j` - Neo4j data migration
- `:postgres` - PostgreSQL database integration
- `:sqlite` - SQLite database integration
- `:unity` - Unity Catalog table scanning
- `:vector` - Vector similarity search (HNSW indexing)

### Managing Extensions

```elixir
# Install and load an extension
:ok = LadybugEx.Extensions.install_and_load(conn, "json")

# Check if an extension is loaded
LadybugEx.Extensions.loaded?(conn, "vector") # => true or false

# List available extensions
{:ok, available} = LadybugEx.Extensions.list_available(conn)

# List currently loaded extensions
{:ok, loaded} = LadybugEx.Extensions.list_loaded(conn)

# Update an extension (re-download from server)
:ok = LadybugEx.Extensions.update(conn, "fts")

# Uninstall an extension
:ok = LadybugEx.Extensions.uninstall(conn, "postgres")

# Install from a specific server
:ok = LadybugEx.Extensions.install_from(conn, "vector", "http://custom-server/")
```

All extension functions also have bang variants (e.g., `install_and_load!`) that raise on error.

## Configuration Options

When opening a database, you can specify various configuration options:

```elixir
LadybugEx.Database.open("/path/to/db",
  buffer_pool_size: 1024 * 1024 * 256,  # 256MB buffer pool
  max_num_threads: 8,                    # Max threads for query execution
  enable_compression: true,              # Enable data compression
  read_only: false,                      # Read-write mode
  max_db_size: 1024 * 1024 * 1024 * 10  # 10GB max size
)
```

## Architecture

The library consists of several layers:

1. **Rust NIF Layer**: Low-level bindings to LadybugDB C++ library
2. **Native Module**: Elixir interface to the Rust NIFs
3. **API Modules**: Idiomatic Elixir APIs for different aspects:
   - `Database`: Database lifecycle management
   - `Connection`: Query execution and connection management
   - `Schema`: DDL operations for tables and indexes
   - `Graph`: High-level graph operations
   - `PreparedStatement`: Parameterized query support
   - `Extensions`: Comprehensive extension management system
   - `Vector`: Vector indexing and similarity search (uses Extensions internally)

## Performance Considerations

- Use prepared statements for repeated queries with different parameters
- Create indexes on frequently queried properties
- Configure appropriate buffer pool size based on your dataset
- Use connection pooling for concurrent operations
- Batch operations within transactions when possible

## Project Status

LadybugEx provides Elixir bindings for LadybugDB via a Rustler NIF. The library is actively maintained and available on Hex.

### Implemented Features

✅ Database lifecycle management (persistent and in-memory modes)
✅ Cypher query execution with parameterized queries
✅ Schema operations (node tables, relationship tables, indexes)
✅ Graph operations (create/find nodes, relationships, shortest path)
✅ Transaction support with automatic rollback
✅ Prepared statements for efficient repeated queries
✅ Comprehensive extension management system for all LadybugDB extensions
✅ Vector search support via LadybugDB's vector extension
✅ Comprehensive test coverage

### Known Limitations

- Extensions must be installed and loaded before use (using INSTALL and LOAD commands)
- Some advanced LadybugDB features may not yet have Elixir bindings
- Resource management relies on Erlang's garbage collector

## Testing

Run the test suite:

```bash
# Run all tests
mix test

# Run tests with specific tags
mix test --only focus

# Run a specific test file
mix test test/ladybug_ex/connection_test.exs
```

All tests pass without requiring external dependencies. The vector extension tests validate both successful operation when the extension can be loaded and proper error handling when it cannot.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
