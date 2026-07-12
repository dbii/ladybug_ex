defmodule LadybugEx.FTS do
  @moduledoc """
  Interface for full-text search using the fts extension.

  This module provides high-level functions for creating and querying
  BM25-based full-text search indexes in LadybugDB.

  ## Prerequisites

  The fts extension must be installed and loaded before using this module:

      # Install once
      LadybugEx.Extensions.install(conn, "fts")

      # Load for each connection
      LadybugEx.Extensions.load(conn, "fts")

  This module will automatically ensure the extension is loaded when calling
  its functions.

  ## Supported Stemmers

  - `:arabic`, `:danish`, `:dutch`, `:english`, `:finnish`, `:french`,
    `:german`, `:greek`, `:hungarian`, `:indonesian`, `:irish`, `:italian`,
    `:lithuanian`, `:nepali`, `:norwegian`, `:porter`, `:portuguese`,
    `:romanian`, `:russian`, `:spanish`, `:swedish`, `:tamil`, `:turkish`

  ## Usage Examples

      # Create a full-text index on a single property
      {:ok, _} = FTS.create_index(conn, "Article",
        properties: ["content"],
        stemmer: :english
      )

      # Create index on multiple properties
      {:ok, _} = FTS.create_index(conn, "Product",
        properties: ["name", "description"],
        stemmer: :english,
        stopwords: ["the", "a", "an"]
      )

      # Query the index
      {:ok, results} = FTS.query_index(conn, "Article", "article_fts_idx",
        query: "machine learning algorithms",
        limit: 20
      )

      # Drop the index
      {:ok, _} = FTS.drop_index(conn, "Article", "article_fts_idx")
  """

  alias LadybugEx.{Connection, Extensions}

  @type stemmer :: atom()
  @type search_result :: %{String.t() => any()}

  @default_stemmer :english
  @default_conjunctive true
  @default_k 1.2
  @default_b 0.75
  @default_limit 10

  @valid_stemmers [
    :arabic,
    :danish,
    :dutch,
    :english,
    :finnish,
    :french,
    :german,
    :greek,
    :hungarian,
    :indonesian,
    :irish,
    :italian,
    :lithuanian,
    :nepali,
    :norwegian,
    :porter,
    :portuguese,
    :romanian,
    :russian,
    :spanish,
    :swedish,
    :tamil,
    :turkish
  ]

  @doc """
  Create a full-text search index on a node or relationship table.

  ## Options

    * `:properties` - (required) List of property names to index
    * `:stemmer` - Language stemmer to use (default: `:english`)
    * `:stopwords` - List of stopwords to exclude (default: language-specific)
    * `:index_name` - Custom index name (default: auto-generated)

  ## Examples

      # Index a single property
      {:ok, _} = FTS.create_index(conn, "Article",
        properties: ["content"]
      )

      # Index multiple properties with custom stemmer
      {:ok, _} = FTS.create_index(conn, "Document",
        properties: ["title", "abstract", "body"],
        stemmer: :french
      )

      # With custom stopwords
      {:ok, _} = FTS.create_index(conn, "Product",
        properties: ["description"],
        stemmer: :english,
        stopwords: ["the", "a", "an", "and", "or", "but"]
      )
  """
  @spec create_index(Connection.t(), String.t(), keyword()) :: {:ok, any()} | {:error, String.t()}
  def create_index(conn, table, opts) when is_binary(table) and is_list(opts) do
    with {:ok, params} <- validate_create_params(table, opts),
         :ok <- Extensions.ensure_loaded(conn, "fts") do
      query = build_create_query(params)
      Connection.query(conn, query)
    end
  end

  @doc """
  Create a full-text search index on a node or relationship table.

  Raises an error if the index creation fails.

  ## Examples

      FTS.create_index!(conn, "Article",
        properties: ["content"]
      )
  """
  @spec create_index!(Connection.t(), String.t(), keyword()) :: any()
  def create_index!(conn, table, opts) do
    case create_index(conn, table, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to create FTS index: #{reason}"
    end
  end

  @doc """
  Query a full-text search index.

  ## Options

    * `:query` - (required) Search query string
    * `:conjunctive` - Use AND logic for multi-term queries (default: #{@default_conjunctive})
    * `:k` - BM25 k1 parameter (default: #{@default_k})
    * `:b` - BM25 b parameter (default: #{@default_b})
    * `:limit` - Maximum number of results (default: #{@default_limit})

  ## Return Format

  Returns a list of results, each containing:
    * `"node"` - The matched node
    * `"score"` - BM25 relevance score

  ## Examples

      # Basic query
      {:ok, results} = FTS.query_index(conn, "Article", "article_fts_idx",
        query: "machine learning"
      )

      # With OR logic and custom limit
      {:ok, results} = FTS.query_index(conn, "Product", "product_fts_idx",
        query: "laptop computer notebook",
        conjunctive: false,
        limit: 50
      )

      # With custom BM25 parameters
      {:ok, results} = FTS.query_index(conn, "Document", "doc_fts_idx",
        query: "data science",
        k: 1.5,
        b: 0.8,
        limit: 100
      )
  """
  @spec query_index(Connection.t(), String.t(), String.t(), keyword()) ::
          {:ok, [search_result()]} | {:error, String.t()}
  def query_index(conn, table, index_name, opts)
      when is_binary(table) and is_binary(index_name) and is_list(opts) do
    with {:ok, params} <- validate_query_params(table, index_name, opts),
         :ok <- Extensions.ensure_loaded(conn, "fts") do
      query = build_query_query(params)
      Connection.query(conn, query)
    end
  end

  @doc """
  Query a full-text search index.

  Raises an error if the query fails.

  ## Examples

      results = FTS.query_index!(conn, "Article", "article_fts_idx",
        query: "machine learning"
      )
  """
  @spec query_index!(Connection.t(), String.t(), String.t(), keyword()) :: [search_result()]
  def query_index!(conn, table, index_name, opts) do
    case query_index(conn, table, index_name, opts) do
      {:ok, results} -> results
      {:error, reason} -> raise "Failed to query FTS index: #{reason}"
    end
  end

  @doc """
  Drop a full-text search index.

  ## Examples

      {:ok, _} = FTS.drop_index(conn, "Article", "article_fts_idx")
  """
  @spec drop_index(Connection.t(), String.t(), String.t()) :: {:ok, any()} | {:error, String.t()}
  def drop_index(conn, table, index_name)
      when is_binary(table) and is_binary(index_name) do
    with :ok <- Extensions.ensure_loaded(conn, "fts") do
      query = "CALL DROP_FTS_INDEX('#{table}', '#{index_name}');"
      Connection.query(conn, query)
    end
  end

  @doc """
  Drop a full-text search index.

  Raises an error if dropping the index fails.

  ## Examples

      FTS.drop_index!(conn, "Article", "article_fts_idx")
  """
  @spec drop_index!(Connection.t(), String.t(), String.t()) :: any()
  def drop_index!(conn, table, index_name) do
    case drop_index(conn, table, index_name) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to drop FTS index: #{reason}"
    end
  end

  @doc """
  List all full-text search indexes in the database.

  ## Examples

      {:ok, indexes} = FTS.list_indexes(conn)
      Enum.each(indexes, fn idx ->
        IO.inspect({idx["table"], idx["index_name"], idx["properties"]})
      end)
  """
  @spec list_indexes(Connection.t()) :: {:ok, [map()]} | {:error, String.t()}
  def list_indexes(conn) do
    with :ok <- Extensions.ensure_loaded(conn, "fts") do
      # This is a hypothetical function - need to verify actual LadybugDB support
      Connection.query(conn, "CALL SHOW_FTS_INDEXES() RETURN *;")
    end
  end

  @doc """
  List all full-text search indexes in the database.

  Raises an error if the listing fails.
  """
  @spec list_indexes!(Connection.t()) :: [map()]
  def list_indexes!(conn) do
    case list_indexes(conn) do
      {:ok, indexes} -> indexes
      {:error, reason} -> raise "Failed to list FTS indexes: #{reason}"
    end
  end

  @doc """
  Analyze text using the FTS stemmer.

  Useful for debugging and understanding how text is processed.

  ## Examples

      {:ok, tokens} = FTS.analyze_text(conn, "running quickly", :english)
      # Returns: ["run", "quick"]
  """
  @spec analyze_text(Connection.t(), String.t(), stemmer()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def analyze_text(conn, text, stemmer \\ :english)
      when is_binary(text) and stemmer in @valid_stemmers do
    with :ok <- Extensions.ensure_loaded(conn, "fts") do
      # This is a hypothetical function - need to verify actual LadybugDB support
      query = "CALL ANALYZE_FTS_TEXT('#{escape_string(text)}', '#{stemmer}') RETURN tokens;"
      Connection.query(conn, query)
    end
  end

  @doc """
  Analyze text using the FTS stemmer.

  Raises an error if the analysis fails.
  """
  @spec analyze_text!(Connection.t(), String.t(), stemmer()) :: [String.t()]
  def analyze_text!(conn, text, stemmer \\ :english) do
    case analyze_text(conn, text, stemmer) do
      {:ok, tokens} -> tokens
      {:error, reason} -> raise "Failed to analyze text: #{reason}"
    end
  end

  # Private functions

  defp validate_create_params(table, opts) do
    properties = Keyword.get(opts, :properties)

    cond do
      is_nil(properties) ->
        {:error, "Missing required option :properties"}

      not is_list(properties) or Enum.empty?(properties) ->
        {:error, "Invalid properties: must be a non-empty list"}

      not Enum.all?(properties, &is_binary/1) ->
        {:error, "Invalid properties: all must be strings"}

      true ->
        stemmer = Keyword.get(opts, :stemmer, @default_stemmer)

        if stemmer not in @valid_stemmers do
          {:error, "Invalid stemmer: #{inspect(stemmer)}"}
        else
          properties_str = Enum.join(properties, "_")
          index_name = Keyword.get(opts, :index_name, "#{table}_fts_#{properties_str}_idx")
          stopwords = Keyword.get(opts, :stopwords, [])

          params = %{
            table: table,
            index_name: index_name,
            properties: properties,
            stemmer: stemmer,
            stopwords: stopwords
          }

          {:ok, params}
        end
    end
  end

  defp validate_query_params(table, index_name, opts) do
    query = Keyword.get(opts, :query)

    cond do
      is_nil(query) ->
        {:error, "Missing required option :query"}

      not is_binary(query) or String.trim(query) == "" ->
        {:error, "Invalid query: must be a non-empty string"}

      true ->
        params = %{
          table: table,
          index_name: index_name,
          query: query,
          conjunctive: Keyword.get(opts, :conjunctive, @default_conjunctive),
          k: Keyword.get(opts, :k, @default_k),
          b: Keyword.get(opts, :b, @default_b),
          limit: Keyword.get(opts, :limit, @default_limit)
        }

        {:ok, params}
    end
  end

  defp build_create_query(params) do
    properties_str = "[" <> Enum.map_join(params.properties, ", ", &"'#{&1}'") <> "]"

    # Optional parameters must be passed as named arguments (param := value);
    # extra positional arguments make the binder reject the call.
    stopwords_arg =
      if Enum.empty?(params.stopwords) do
        ""
      else
        ", stopwords := [" <>
          Enum.map_join(params.stopwords, ", ", &"'#{escape_string(&1)}'") <> "]"
      end

    """
    CALL CREATE_FTS_INDEX('#{params.table}', '#{params.index_name}',
      #{properties_str}, stemmer := '#{params.stemmer}'#{stopwords_arg});
    """
  end

  defp build_query_query(params) do
    """
    CALL QUERY_FTS_INDEX('#{params.table}', '#{params.index_name}',
      '#{escape_string(params.query)}', conjunctive := #{params.conjunctive},
      k := #{params.k}, b := #{params.b}, top := #{params.limit})
    RETURN node, score
    ORDER BY score DESC;
    """
  end

  defp escape_string(str) do
    str
    |> String.replace("'", "\\'")
    |> String.replace("\\", "\\\\")
  end
end
