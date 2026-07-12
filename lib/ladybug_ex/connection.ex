defmodule LadybugEx.Connection do
  @moduledoc """
  Module for managing connections to a LadybugDB database.

  A connection is required to execute queries against a database.
  Multiple connections can be created for the same database to enable
  concurrent operations, though write queries must be executed sequentially.
  """

  alias LadybugEx.{Database, Native, PreparedStatement}

  @type t :: reference()

  @doc """
  Creates a new connection to a database.

  ## Parameters

    * `database` - A database reference obtained from `LadybugEx.Database.open/2` or `LadybugEx.Database.in_memory/1`

  ## Examples

      iex> {:ok, db} = LadybugEx.Database.in_memory()
      iex> {:ok, conn} = LadybugEx.Connection.new(db)
      {:ok, #Reference<...>}

  ## Returns

    * `{:ok, connection}` - Successfully created connection
    * `{:error, reason}` - Error creating connection

  """
  @spec new(Database.t()) :: {:ok, t()} | {:error, String.t()}
  def new(database) do
    Native.new_connection(database)
  end

  @doc """
  Creates a new connection to a database, raising on error.

  Same as `new/1` but raises an exception on error.

  ## Examples

      iex> db = LadybugEx.Database.in_memory!()
      iex> conn = LadybugEx.Connection.new!(db)
      #Reference<...>

  """
  @spec new!(Database.t()) :: t()
  def new!(database) do
    case new(database) do
      {:ok, conn} -> conn
      {:error, reason} -> raise "Failed to create connection: #{reason}"
    end
  end

  @doc """
  Executes a Cypher query and returns all results.

  ## Parameters

    * `connection` - A connection reference
    * `query` - A Cypher query string
    * `opts` - Optional query options

  ## Options

    * `:timeout` - Query timeout in milliseconds

  ## Examples

      iex> LadybugEx.Connection.query(conn, "CREATE NODE TABLE Person(name STRING, age INT64, PRIMARY KEY(name));")
      {:ok, []}

      iex> LadybugEx.Connection.query(conn, "CREATE (:Person {name: 'Alice', age: 25});")
      {:ok, []}

      iex> LadybugEx.Connection.query(conn, "MATCH (p:Person) RETURN p.name AS name, p.age AS age;")
      {:ok, [%{name: "Alice", age: 25}]}

  ## Returns

    * `{:ok, results}` - List of result rows, where each row is a map
    * `{:error, reason}` - Query execution error

  """
  @spec query(t(), String.t(), keyword()) :: {:ok, list(map())} | {:error, String.t()}
  def query(connection, query, _opts \\ []) when is_binary(query) do
    Native.query(connection, query)
  end

  @doc """
  Executes a Cypher query and returns all results, raising on error.

  Same as `query/3` but raises an exception on error.

  ## Examples

      iex> LadybugEx.Connection.query!(conn, "MATCH (p:Person) RETURN p.name AS name;")
      [%{name: "Alice"}]

  """
  @spec query!(t(), String.t(), keyword()) :: list(map())
  def query!(connection, query, opts \\ []) do
    case query(connection, query, opts) do
      {:ok, results} -> results
      {:error, reason} -> raise "Query failed: #{reason}"
    end
  end

  @doc """
  Prepares a Cypher query for repeated execution with different parameters.

  Prepared statements are useful when you need to execute the same query
  multiple times with different parameters, as it avoids re-parsing and
  re-planning the query.

  ## Parameters

    * `connection` - A connection reference
    * `query` - A Cypher query string with parameter placeholders (e.g., `$name`)

  ## Examples

      iex> {:ok, prepared} = LadybugEx.Connection.prepare(conn,
      ...>   "CREATE (:Person {name: $name, age: $age});"
      ...> )
      {:ok, #Reference<...>}

  ## Returns

    * `{:ok, prepared_statement}` - Successfully prepared statement
    * `{:error, reason}` - Error preparing statement

  """
  @spec prepare(t(), String.t()) :: {:ok, PreparedStatement.t()} | {:error, String.t()}
  def prepare(connection, query) when is_binary(query) do
    Native.prepare(connection, query)
  end

  @doc """
  Prepares a Cypher query, raising on error.

  Same as `prepare/2` but raises an exception on error.
  """
  @spec prepare!(t(), String.t()) :: PreparedStatement.t()
  def prepare!(connection, query) do
    case prepare(connection, query) do
      {:ok, prepared} -> prepared
      {:error, reason} -> raise "Failed to prepare statement: #{reason}"
    end
  end

  @doc """
  Executes a prepared statement with the given parameters.

  ## Parameters

    * `connection` - A connection reference
    * `prepared` - A prepared statement reference from `prepare/2`
    * `params` - A keyword list or map of parameter values

  ## Examples

      iex> prepared = LadybugEx.Connection.prepare!(conn,
      ...>   "CREATE (:Person {name: $name, age: $age});"
      ...> )
      iex> LadybugEx.Connection.execute(conn, prepared,
      ...>   name: "Bob",
      ...>   age: 30
      ...> )
      {:ok, []}

      # Using a map for parameters
      iex> LadybugEx.Connection.execute(conn, prepared,
      ...>   %{name: "Charlie", age: 35}
      ...> )
      {:ok, []}

  ## Returns

    * `{:ok, results}` - Query results
    * `{:error, reason}` - Execution error

  """
  @spec execute(t(), PreparedStatement.t(), keyword() | map()) ::
          {:ok, list(map())} | {:error, String.t()}
  def execute(connection, prepared, params) when is_list(params) or is_map(params) do
    params_list =
      case params do
        params when is_map(params) ->
          Enum.map(params, fn {k, v} -> {to_string(k), v} end)

        params when is_list(params) ->
          Enum.map(params, fn {k, v} -> {to_string(k), v} end)
      end

    Native.execute(connection, prepared, params_list)
  end

  @doc """
  Executes a prepared statement with parameters, raising on error.

  Same as `execute/3` but raises an exception on error.
  """
  @spec execute!(t(), PreparedStatement.t(), keyword() | map()) :: list(map())
  def execute!(connection, prepared, params) do
    case execute(connection, prepared, params) do
      {:ok, results} -> results
      {:error, reason} -> raise "Execution failed: #{reason}"
    end
  end

  @doc """
  Runs a function within a transaction.

  If the function returns `{:ok, value}`, the transaction is committed and `{:ok, value}` is returned.
  If the function returns `{:error, reason}` or raises an exception, the transaction is rolled back.

  Note: This is a convenience function that wraps BEGIN TRANSACTION and COMMIT/ROLLBACK queries.

  ## Parameters

    * `connection` - A connection reference
    * `fun` - A function that takes the connection and performs operations

  ## Examples

      iex> LadybugEx.Connection.transaction(conn, fn conn ->
      ...>   with {:ok, _} <- LadybugEx.Connection.query(conn, "CREATE (:Person {name: 'Alice'});"),
      ...>        {:ok, _} <- LadybugEx.Connection.query(conn, "CREATE (:Person {name: 'Bob'});") do
      ...>     {:ok, :success}
      ...>   end
      ...> end)
      {:ok, :success}

  """
  @spec transaction(t(), (t() -> {:ok, any()} | {:error, any()})) ::
          {:ok, any()} | {:error, any()}
  def transaction(connection, fun) when is_function(fun, 1) do
    with {:ok, _} <- query(connection, "BEGIN TRANSACTION;") do
      case fun.(connection) do
        {:ok, _result} = success ->
          case query(connection, "COMMIT;") do
            {:ok, _} -> success
            error -> error
          end

        {:error, _reason} = error ->
          query(connection, "ROLLBACK;")
          error

        other ->
          query(connection, "ROLLBACK;")
          {:error, {:invalid_transaction_result, other}}
      end
    else
      error ->
        error
    end
  rescue
    exception ->
      query(connection, "ROLLBACK;")
      reraise exception, __STACKTRACE__
  end

  @doc """
  Sets the maximum number of threads for query execution on this connection.

  ## Parameters

    * `connection` - A connection reference
    * `num_threads` - Maximum number of threads

  ## Examples

      iex> LadybugEx.Connection.set_max_threads(conn, 4)
      :ok

  """
  @spec set_max_threads(t(), pos_integer()) :: :ok | {:error, String.t()}
  def set_max_threads(_connection, num_threads)
      when is_integer(num_threads) and num_threads > 0 do
    # This would be implemented in the NIF
    {:error, "Not yet implemented"}
  end

  @doc """
  Interrupts any running query on this connection.

  Useful for cancelling long-running queries from another process.

  ## Parameters

    * `connection` - A connection reference

  ## Examples

      iex> LadybugEx.Connection.interrupt(conn)
      :ok

  """
  @spec interrupt(t()) :: :ok | {:error, String.t()}
  def interrupt(_connection) do
    # This would be implemented in the NIF
    {:error, "Not yet implemented"}
  end

  @doc """
  Sets a query timeout for this connection.

  ## Parameters

    * `connection` - A connection reference
    * `timeout_ms` - Timeout in milliseconds

  ## Examples

      iex> LadybugEx.Connection.set_query_timeout(conn, 5000)
      :ok

  """
  @spec set_query_timeout(t(), non_neg_integer()) :: :ok | {:error, String.t()}
  def set_query_timeout(_connection, timeout_ms)
      when is_integer(timeout_ms) and timeout_ms >= 0 do
    # This would be implemented in the NIF
    {:error, "Not yet implemented"}
  end
end
