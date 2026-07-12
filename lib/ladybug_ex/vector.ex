defmodule LadybugEx.Vector do
  @moduledoc """
  Interface for vector similarity search using the vector extension.

  This module provides high-level functions for creating and querying
  HNSW (Hierarchical Navigable Small World) vector indexes in LadybugDB.

  ## Prerequisites

  The vector extension must be installed and loaded before using this module:

      # Install once
      LadybugEx.Extensions.install(conn, "vector")

      # Load for each connection
      LadybugEx.Extensions.load(conn, "vector")

  This module will automatically ensure the extension is loaded when calling
  its functions.

  ## Supported Distance Metrics

  - `:cosine` - Cosine similarity (default)
  - `:l2` - Euclidean distance
  - `:l2sq` - Squared Euclidean distance
  - `:dotproduct` - Dot product similarity

  ## Usage Examples

      # Create a vector index
      {:ok, _} = Vector.create_index(conn, "Product",
        property: "embedding",
        dimension: 1536,
        metric: :cosine
      )

      # Query the index
      {:ok, results} = Vector.query_index(conn, "Product", "product_embedding_idx",
        vector: embedding,
        k: 10
      )

      # Drop the index
      {:ok, _} = Vector.drop_index(conn, "Product", "product_embedding_idx")

  ## Filtered Search with Projected Graphs

  For filtered vector search, first create a projected graph:

      # Create a filtered projection
      {:ok, _} = Connection.query(conn, \"\"\"
        CALL PROJECT_GRAPH('filtered_products', 'Product', '*')
        WHERE n.category = 'electronics'
        RETURN *
      \"\"\")

      # Query on the projected graph
      {:ok, results} = Vector.query_index(conn, "filtered_products", "product_embedding_idx",
        vector: embedding,
        k: 10
      )
  """

  alias LadybugEx.{Connection, Extensions}

  @type metric :: :cosine | :l2 | :l2sq | :dotproduct
  @type vector :: [float()]
  @type search_result :: %{String.t() => any()}

  @default_mu 30
  @default_ml 30
  @default_pu 0.05
  @default_efc 200
  @default_efs 200
  @default_cache_embeddings false

  @doc """
  Create a vector index on a node or relationship table.

  ## Options

    * `:property` - (required) The property name containing vectors
    * `:dimension` - (required) The dimension of the vectors
    * `:metric` - Distance metric to use (default: `:cosine`)
    * `:mu` - HNSW M parameter for index building (default: #{@default_mu})
    * `:ml` - HNSW M parameter for layer 0 (default: #{@default_ml})
    * `:pu` - HNSW percentage of nodes in upper layers, 0.0-1.0 (default: #{@default_pu})
    * `:efc` - HNSW ef parameter for construction (default: #{@default_efc})
    * `:cache_embeddings` - Whether to cache embeddings (default: #{@default_cache_embeddings})
    * `:index_name` - Custom index name (default: auto-generated)

  ## Examples

      # Basic usage with required options
      {:ok, _} = Vector.create_index(conn, "Product",
        property: "embedding",
        dimension: 1536
      )

      # With custom parameters
      {:ok, _} = Vector.create_index(conn, "Product",
        property: "embedding",
        dimension: 768,
        metric: :l2,
        mu: 50,
        ml: 50,
        efc: 400,
        index_name: "custom_product_idx"
      )
  """
  @spec create_index(Connection.t(), String.t(), keyword()) :: {:ok, any()} | {:error, String.t()}
  def create_index(conn, table, opts) when is_binary(table) and is_list(opts) do
    with {:ok, params} <- validate_create_params(table, opts),
         :ok <- Extensions.ensure_loaded(conn, "vector") do
      query = build_create_query(params)
      Connection.query(conn, query)
    end
  end

  @doc """
  Create a vector index on a node or relationship table.

  Raises an error if the index creation fails.

  ## Examples

      Vector.create_index!(conn, "Product",
        property: "embedding",
        dimension: 1536
      )
  """
  @spec create_index!(Connection.t(), String.t(), keyword()) :: any()
  def create_index!(conn, table, opts) do
    case create_index(conn, table, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to create vector index: #{reason}"
    end
  end

  @doc """
  Query a vector index to find the k-nearest neighbors.

  ## Options

    * `:vector` - (required) Query vector to search for
    * `:k` - (required) Number of nearest neighbors to return
    * `:efs` - HNSW ef parameter for search (default: #{@default_efs})

  ## Return Format

  Returns a list of results, each containing:
    * `"node"` - The matched node
    * `"distance"` - Distance to the query vector

  ## Examples

      # Basic query
      {:ok, results} = Vector.query_index(conn, "Product", "product_embedding_idx",
        vector: [0.1, 0.2, 0.3, ...],
        k: 10
      )

      # With custom search parameter
      {:ok, results} = Vector.query_index(conn, "Product", "product_embedding_idx",
        vector: embedding,
        k: 20,
        efs: 400
      )

      # Access results
      Enum.each(results, fn result ->
        node = result["node"]
        distance = result["distance"]
        IO.inspect({node["name"], distance})
      end)
  """
  @spec query_index(Connection.t(), String.t(), String.t(), keyword()) ::
          {:ok, [search_result()]} | {:error, String.t()}
  def query_index(conn, table, index_name, opts)
      when is_binary(table) and is_binary(index_name) and is_list(opts) do
    with {:ok, params} <- validate_query_params(table, index_name, opts),
         :ok <- Extensions.ensure_loaded(conn, "vector") do
      query = build_query_query(params)
      Connection.query(conn, query)
    end
  end

  @doc """
  Query a vector index to find the k-nearest neighbors.

  Raises an error if the query fails.

  ## Examples

      results = Vector.query_index!(conn, "Product", "product_embedding_idx",
        vector: embedding,
        k: 10
      )
  """
  @spec query_index!(Connection.t(), String.t(), String.t(), keyword()) :: [search_result()]
  def query_index!(conn, table, index_name, opts) do
    case query_index(conn, table, index_name, opts) do
      {:ok, results} -> results
      {:error, reason} -> raise "Failed to query vector index: #{reason}"
    end
  end

  @doc """
  Drop a vector index.

  ## Examples

      {:ok, _} = Vector.drop_index(conn, "Product", "product_embedding_idx")
  """
  @spec drop_index(Connection.t(), String.t(), String.t()) :: {:ok, any()} | {:error, String.t()}
  def drop_index(conn, table, index_name)
      when is_binary(table) and is_binary(index_name) do
    with :ok <- Extensions.ensure_loaded(conn, "vector") do
      query = "CALL DROP_VECTOR_INDEX('#{table}', '#{index_name}');"
      Connection.query(conn, query)
    end
  end

  @doc """
  Drop a vector index.

  Raises an error if dropping the index fails.

  ## Examples

      Vector.drop_index!(conn, "Product", "product_embedding_idx")
  """
  @spec drop_index!(Connection.t(), String.t(), String.t()) :: any()
  def drop_index!(conn, table, index_name) do
    case drop_index(conn, table, index_name) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to drop vector index: #{reason}"
    end
  end

  @doc """
  List all vector indexes in the database.

  ## Examples

      {:ok, indexes} = Vector.list_indexes(conn)
      Enum.each(indexes, fn idx ->
        IO.inspect({idx["table"], idx["index_name"], idx["property"]})
      end)
  """
  @spec list_indexes(Connection.t()) :: {:ok, [map()]} | {:error, String.t()}
  def list_indexes(conn) do
    with :ok <- Extensions.ensure_loaded(conn, "vector") do
      # This is a hypothetical function - need to verify actual LadybugDB support
      Connection.query(conn, "CALL SHOW_VECTOR_INDEXES() RETURN *;")
    end
  end

  @doc """
  List all vector indexes in the database.

  Raises an error if the listing fails.
  """
  @spec list_indexes!(Connection.t()) :: [map()]
  def list_indexes!(conn) do
    case list_indexes(conn) do
      {:ok, indexes} -> indexes
      {:error, reason} -> raise "Failed to list vector indexes: #{reason}"
    end
  end

  # Private functions

  defp validate_create_params(table, opts) do
    property = Keyword.get(opts, :property)
    dimension = Keyword.get(opts, :dimension)

    cond do
      is_nil(property) ->
        {:error, "Missing required option :property"}

      is_nil(dimension) ->
        {:error, "Missing required option :dimension"}

      not is_integer(dimension) or dimension <= 0 ->
        {:error, "Invalid dimension: must be a positive integer"}

      true ->
        metric = Keyword.get(opts, :metric, :cosine)
        index_name = Keyword.get(opts, :index_name, "#{table}_#{property}_idx")

        params = %{
          table: table,
          index_name: index_name,
          property: property,
          dimension: dimension,
          metric: validate_metric(metric),
          mu: Keyword.get(opts, :mu, @default_mu),
          ml: Keyword.get(opts, :ml, @default_ml),
          pu: Keyword.get(opts, :pu, @default_pu),
          efc: Keyword.get(opts, :efc, @default_efc),
          cache_embeddings: Keyword.get(opts, :cache_embeddings, @default_cache_embeddings)
        }

        {:ok, params}
    end
  end

  defp validate_query_params(table, index_name, opts) do
    vector = Keyword.get(opts, :vector)
    k = Keyword.get(opts, :k)

    cond do
      is_nil(vector) ->
        {:error, "Missing required option :vector"}

      not is_list(vector) or not Enum.all?(vector, &is_number/1) ->
        {:error, "Invalid vector: must be a list of numbers"}

      is_nil(k) ->
        {:error, "Missing required option :k"}

      not is_integer(k) or k <= 0 ->
        {:error, "Invalid k: must be a positive integer"}

      true ->
        params = %{
          table: table,
          index_name: index_name,
          vector: vector,
          k: k,
          efs: Keyword.get(opts, :efs, @default_efs)
        }

        {:ok, params}
    end
  end

  defp validate_metric(metric) when metric in [:cosine, :l2, :l2sq, :dotproduct], do: metric
  defp validate_metric(metric), do: raise("Invalid metric: #{inspect(metric)}")

  defp build_create_query(params) do
    # Optional parameters must be passed as named arguments (param := value);
    # extra positional arguments make the binder reject the call.
    """
    CALL CREATE_VECTOR_INDEX('#{params.table}', '#{params.index_name}', '#{params.property}',
      mu := #{params.mu}, ml := #{params.ml}, pu := #{:erlang.float(params.pu)},
      metric := '#{params.metric}', efc := #{params.efc},
      cache_embeddings := #{params.cache_embeddings});
    """
  end

  defp build_query_query(params) do
    vector_str = "[" <> Enum.map_join(params.vector, ", ", &to_string/1) <> "]"

    """
    CALL QUERY_VECTOR_INDEX('#{params.table}', '#{params.index_name}',
      #{vector_str}, #{params.k}, efs := #{params.efs})
    RETURN node, distance
    ORDER BY distance;
    """
  end
end
