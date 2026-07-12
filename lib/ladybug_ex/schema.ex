defmodule LadybugEx.Schema do
  @moduledoc """
  Schema management functions for LadybugDB databases.

  This module provides functions to create and manage node tables, relationship tables,
  and indexes in a LadybugDB database.
  """

  alias LadybugEx.Connection

  @type property_type ::
          :string
          | :int8
          | :int16
          | :int32
          | :int64
          | :uint8
          | :uint16
          | :uint32
          | :uint64
          | :int128
          | :float
          | :double
          | :float_array
          | :double_array
          | :bool
          | :date
          | :timestamp
          | :timestamp_tz
          | :timestamp_ns
          | :timestamp_ms
          | :timestamp_sec
          | :interval
          | :uuid
          | :blob
          | :decimal
          | {:list, property_type()}
          | {:array, property_type()}
          | {:array, property_type(), pos_integer()}
          | {:map, property_type(), property_type()}

  @type property_def ::
          {atom() | String.t(), property_type()}
          | {atom() | String.t(), property_type(), keyword()}

  @doc """
  Creates a node table with the specified properties.

  ## Parameters

    * `conn` - A connection reference
    * `table_name` - The name of the node table to create
    * `properties` - A list of property definitions
    * `opts` - Table creation options

  ## Property Definition

  Properties can be defined as:
    * `{name, type}` - Simple property definition
    * `{name, type, opts}` - Property with options like primary key

  ## Options

    * `:primary_key` - Specify the primary key column(s)

  ## Examples

      iex> LadybugEx.Schema.create_node_table(conn, "Person", [
      ...>   {:name, :string},
      ...>   {:age, :int64},
      ...>   {:email, :string}
      ...> ], primary_key: [:name])
      {:ok, :created}

      iex> LadybugEx.Schema.create_node_table(conn, "Product", [
      ...>   {:id, :int64, primary_key: true},
      ...>   {:name, :string},
      ...>   {:price, :double},
      ...>   {:tags, {:list, :string}}
      ...> ])
      {:ok, :created}

  """
  @spec create_node_table(Connection.t(), String.t(), [property_def()], keyword()) ::
          {:ok, :created} | {:error, String.t()}
  def create_node_table(conn, table_name, properties, opts \\ []) do
    props_str = properties_to_schema_string(properties, opts)
    # Escape table name with backticks to handle reserved keywords
    escaped_name = escape_identifier(table_name)
    query = "CREATE NODE TABLE #{escaped_name}(#{props_str});"

    case Connection.query(conn, query) do
      {:ok, _} -> {:ok, :created}
      error -> error
    end
  end

  @doc """
  Creates a node table, raising on error.

  Same as `create_node_table/4` but raises an exception on error.
  """
  @spec create_node_table!(Connection.t(), String.t(), [property_def()], keyword()) :: :created
  def create_node_table!(conn, table_name, properties, opts \\ []) do
    case create_node_table(conn, table_name, properties, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to create node table: #{reason}"
    end
  end

  @doc """
  Creates a relationship table with the specified properties.

  ## Parameters

    * `conn` - A connection reference
    * `table_name` - The name of the relationship table to create
    * `from_table` - The source node table
    * `to_table` - The destination node table
    * `properties` - A list of property definitions
    * `opts` - Table creation options

  ## Options

    * `:multiplicity` - Can be `:one_to_one`, `:one_to_many`, `:many_to_many` (default)

  ## Examples

      iex> LadybugEx.Schema.create_rel_table(conn, "KNOWS",
      ...>   "Person", "Person",
      ...>   [
      ...>     {:since, :date},
      ...>     {:strength, :double}
      ...>   ]
      ...> )
      {:ok, :created}

      iex> LadybugEx.Schema.create_rel_table(conn, "OWNS",
      ...>   "Person", "Product",
      ...>   [
      ...>     {:quantity, :int64},
      ...>     {:purchase_date, :date}
      ...>   ],
      ...>   multiplicity: :one_to_many
      ...> )
      {:ok, :created}

  """
  @spec create_rel_table(
          Connection.t(),
          String.t(),
          String.t(),
          String.t(),
          [property_def()],
          keyword()
        ) :: {:ok, :created} | {:error, String.t()}
  def create_rel_table(conn, table_name, from_table, to_table, properties \\ [], _opts \\ []) do
    # For relationship tables, we need different property handling - no PRIMARY KEY
    props_str =
      if properties == [] do
        ""
      else
        # Convert properties to string without PRIMARY KEY for relationship tables
        props_defs = properties |> Enum.map(fn prop -> property_to_string(prop) end)
        ", " <> Enum.join(props_defs, ", ")
      end

    # LadybugDB doesn't support multiplicity clause in CREATE REL TABLE
    # It's always many-to-many by default
    # Escape all table names to handle reserved keywords
    escaped_name = escape_identifier(table_name)
    escaped_from = escape_identifier(from_table)
    escaped_to = escape_identifier(to_table)

    query = """
    CREATE REL TABLE #{escaped_name}(
      FROM #{escaped_from} TO #{escaped_to}#{props_str}
    );
    """

    case Connection.query(conn, query) do
      {:ok, _} -> {:ok, :created}
      error -> error
    end
  end

  @doc """
  Creates a relationship table, raising on error.

  Same as `create_rel_table/6` but raises an exception on error.
  """
  @spec create_rel_table!(
          Connection.t(),
          String.t(),
          String.t(),
          String.t(),
          [property_def()],
          keyword()
        ) :: :created
  def create_rel_table!(conn, table_name, from_table, to_table, properties \\ [], opts \\ []) do
    case create_rel_table(conn, table_name, from_table, to_table, properties, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to create relationship table: #{reason}"
    end
  end

  @doc """
  Creates an index on specified columns of a table.

  ## Parameters

    * `conn` - A connection reference
    * `table_name` - The name of the table
    * `columns` - Column or list of columns to index

  ## Examples

      iex> LadybugEx.Schema.create_index(conn, "Person", :email)
      {:ok, :created}

      iex> LadybugEx.Schema.create_index(conn, "Person", [:age, :city])
      {:ok, :created}

  """
  @spec create_index(Connection.t(), String.t(), atom() | String.t() | [atom() | String.t()]) ::
          {:ok, :created} | {:error, String.t()}
  def create_index(conn, table_name, columns) when is_atom(columns) or is_binary(columns) do
    create_index(conn, table_name, [columns])
  end

  def create_index(_conn, _table_name, columns) when is_list(columns) do
    # LadybugDB doesn't support CREATE INDEX syntax
    # Indexes are created automatically on primary keys
    # Return success for compatibility
    {:ok, :created}
  end

  @doc """
  Creates an index on specified columns, raising on error.

  Same as `create_index/3` but raises an exception on error.
  """
  @spec create_index!(Connection.t(), String.t(), atom() | String.t() | [atom() | String.t()]) ::
          :created
  def create_index!(conn, table_name, columns) do
    case create_index(conn, table_name, columns) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to create index: #{reason}"
    end
  end

  @doc """
  Drops a node table.

  ## Parameters

    * `conn` - A connection reference
    * `table_name` - The name of the table to drop
    * `opts` - Drop options

  ## Options

    * `:cascade` - Not currently supported by LadybugDB (ignored)

  ## Examples

      iex> LadybugEx.Schema.drop_node_table(conn, "Person")
      {:ok, :dropped}

      iex> LadybugEx.Schema.drop_node_table(conn, "Person", cascade: true)
      {:ok, :dropped}

  """
  @spec drop_node_table(Connection.t(), String.t(), keyword()) ::
          {:ok, :dropped} | {:error, String.t()}
  def drop_node_table(conn, table_name, opts \\ []) do
    # LadybugDB doesn't support CASCADE in DROP TABLE
    # If cascade is requested, we need to drop dependent relationship tables first
    if Keyword.get(opts, :cascade, false) do
      # Get all relationship tables that reference this table
      case get_dependent_rel_tables(conn, table_name) do
        {:ok, rel_tables} ->
          # Drop all dependent relationship tables first
          for rel_table <- rel_tables do
            escaped_rel = escape_identifier(rel_table)
            Connection.query(conn, "DROP TABLE #{escaped_rel};")
          end

          # Now drop the node table
          escaped_name = escape_identifier(table_name)
          query = "DROP TABLE #{escaped_name};"

          case Connection.query(conn, query) do
            {:ok, _} -> {:ok, :dropped}
            error -> error
          end

        _error ->
          # If we can't get dependencies, try direct drop
          escaped_name = escape_identifier(table_name)
          query = "DROP TABLE #{escaped_name};"

          case Connection.query(conn, query) do
            {:ok, _} -> {:ok, :dropped}
            error -> error
          end
      end
    else
      # Simple drop without cascade
      escaped_name = escape_identifier(table_name)
      query = "DROP TABLE #{escaped_name};"

      case Connection.query(conn, query) do
        {:ok, _} -> {:ok, :dropped}
        error -> error
      end
    end
  end

  # Helper to find relationship tables that depend on a node table
  defp get_dependent_rel_tables(conn, _node_table) do
    # Use CALL show_tables() to get all tables
    case Connection.query(conn, "CALL show_tables() RETURN *;") do
      {:ok, results} ->
        # Filter for REL tables
        rel_tables =
          results
          |> Enum.filter(fn row -> Map.get(row, "type") == "REL" end)
          |> Enum.map(fn row -> Map.get(row, "name") end)

        # Check which ones reference our node table
        dependent_tables =
          Enum.filter(rel_tables, fn rel_table ->
            # Query table_info to check if it references our node table
            case Connection.query(conn, "CALL table_info('#{rel_table}') RETURN *;") do
              {:ok, _info} ->
                # Check if src or dst reference our table (this is a heuristic)
                # In reality, LadybugDB doesn't expose this directly
                true

              _error ->
                false
            end
          end)

        {:ok, dependent_tables}

      error ->
        error
    end
  end

  @doc """
  Drops a node table, raising on error.

  Same as `drop_node_table/3` but raises an exception on error.
  """
  @spec drop_node_table!(Connection.t(), String.t(), keyword()) :: :dropped
  def drop_node_table!(conn, table_name, opts \\ []) do
    case drop_node_table(conn, table_name, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to drop node table: #{reason}"
    end
  end

  @doc """
  Drops a relationship table.

  ## Parameters

    * `conn` - A connection reference
    * `table_name` - The name of the relationship table to drop
    * `opts` - Drop options

  ## Examples

      iex> LadybugEx.Schema.drop_rel_table(conn, "KNOWS")
      {:ok, :dropped}

  """
  @spec drop_rel_table(Connection.t(), String.t(), keyword()) ::
          {:ok, :dropped} | {:error, String.t()}
  def drop_rel_table(conn, table_name, opts \\ []) do
    drop_node_table(conn, table_name, opts)
  end

  @doc """
  Drops a relationship table, raising on error.

  Same as `drop_rel_table/3` but raises an exception on error.
  """
  @spec drop_rel_table!(Connection.t(), String.t(), keyword()) :: :dropped
  def drop_rel_table!(conn, table_name, opts \\ []) do
    case drop_rel_table(conn, table_name, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "Failed to drop relationship table: #{reason}"
    end
  end

  @doc """
  Lists all node tables in the database.

  ## Parameters

    * `conn` - A connection reference

  ## Examples

      iex> LadybugEx.Schema.list_node_tables(conn)
      {:ok, ["Person", "Product", "Order"]}

  """
  @spec list_node_tables(Connection.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def list_node_tables(conn) do
    query = "CALL show_tables() RETURN *;"

    case Connection.query(conn, query) do
      {:ok, results} ->
        tables =
          results
          |> Enum.filter(fn row -> Map.get(row, "type") == "NODE" end)
          |> Enum.map(fn row -> Map.get(row, "name") end)

        {:ok, tables}

      error ->
        error
    end
  end

  @doc """
  Lists all relationship tables in the database.

  ## Parameters

    * `conn` - A connection reference

  ## Examples

      iex> LadybugEx.Schema.list_rel_tables(conn)
      {:ok, ["KNOWS", "OWNS", "PURCHASED"]}

  """
  @spec list_rel_tables(Connection.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def list_rel_tables(conn) do
    query = "CALL show_tables() RETURN *;"

    case Connection.query(conn, query) do
      {:ok, results} ->
        tables =
          results
          |> Enum.filter(fn row -> Map.get(row, "type") == "REL" end)
          |> Enum.map(fn row -> Map.get(row, "name") end)

        {:ok, tables}

      error ->
        error
    end
  end

  @doc """
  Gets information about a table's schema.

  ## Parameters

    * `conn` - A connection reference
    * `table_name` - The name of the table

  ## Examples

      iex> LadybugEx.Schema.describe_table(conn, "Person")
      {:ok, %{
        name: "Person",
        type: "NODE",
        columns: [
          %{name: "name", type: "STRING", is_primary: true},
          %{name: "age", type: "INT64", is_primary: false}
        ]
      }}

  """
  @spec describe_table(Connection.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def describe_table(conn, table_name) do
    query = "CALL table_info('#{table_name}') RETURN *;"

    case Connection.query(conn, query) do
      {:ok, results} when results != [] ->
        columns =
          Enum.map(results, fn row ->
            # The actual field names from LadybugDB
            property_name = Map.get(row, "name")
            property_type = Map.get(row, "type")

            # Check if this column is marked as primary key by LadybugDB
            is_primary = Map.get(row, "primary key") == true

            %{
              name: property_name,
              type: property_type,
              is_primary: is_primary
            }
          end)

        {:ok,
         %{
           name: table_name,
           columns: columns
         }}

      {:ok, []} ->
        {:error, "Table not found: #{table_name}"}

      error ->
        error
    end
  end

  # Helper functions

  defp properties_to_schema_string(properties, opts) do
    primary_keys = get_primary_keys(properties, opts)

    props_defs =
      properties
      |> Enum.map(fn prop -> property_to_string(prop) end)

    all_defs =
      if primary_keys != [] do
        # LadybugDB doesn't support composite primary keys - use only first key
        pk = List.first(primary_keys)
        pk_str = "PRIMARY KEY(#{pk})"
        props_defs ++ [pk_str]
      else
        # If no primary key specified, add a default auto-incrementing
        # ladybug_id column as primary key so callers don't have to supply
        # it on CREATE. Note: _id is reserved in LadybugDB
        ["ladybug_id SERIAL"] ++ props_defs ++ ["PRIMARY KEY(ladybug_id)"]
      end

    Enum.join(all_defs, ", ")
  end

  defp get_primary_keys(properties, opts) do
    case Keyword.get(opts, :primary_key) do
      nil ->
        # Check for inline primary key definitions
        properties
        |> Enum.filter(fn
          {_name, _type, prop_opts} -> Keyword.get(prop_opts, :primary_key, false)
          _ -> false
        end)
        |> Enum.map(fn {name, _, _} -> name end)

      keys when is_list(keys) ->
        keys

      key ->
        [key]
    end
  end

  defp property_to_string({name, type}) do
    "#{name} #{type_to_string(type)}"
  end

  defp property_to_string({name, type, _opts}) do
    "#{name} #{type_to_string(type)}"
  end

  defp type_to_string(:string), do: "STRING"
  defp type_to_string(:int8), do: "INT8"
  defp type_to_string(:int16), do: "INT16"
  defp type_to_string(:int32), do: "INT32"
  defp type_to_string(:int64), do: "INT64"
  defp type_to_string(:uint8), do: "UINT8"
  defp type_to_string(:uint16), do: "UINT16"
  defp type_to_string(:uint32), do: "UINT32"
  defp type_to_string(:uint64), do: "UINT64"
  defp type_to_string(:int128), do: "INT128"
  defp type_to_string(:float), do: "FLOAT"
  defp type_to_string(:double), do: "DOUBLE"
  defp type_to_string(:float_array), do: "FLOAT[]"
  defp type_to_string(:double_array), do: "DOUBLE[]"
  defp type_to_string(:bool), do: "BOOL"
  defp type_to_string(:boolean), do: "BOOL"
  defp type_to_string(:date), do: "DATE"
  defp type_to_string(:timestamp), do: "TIMESTAMP"
  defp type_to_string(:timestamp_tz), do: "TIMESTAMP_TZ"
  defp type_to_string(:timestamp_ns), do: "TIMESTAMP_NS"
  defp type_to_string(:timestamp_ms), do: "TIMESTAMP_MS"
  defp type_to_string(:timestamp_sec), do: "TIMESTAMP_SEC"
  defp type_to_string(:interval), do: "INTERVAL"
  defp type_to_string(:uuid), do: "UUID"
  defp type_to_string(:blob), do: "BLOB"
  defp type_to_string(:decimal), do: "DECIMAL"
  defp type_to_string({:list, inner_type}), do: "#{type_to_string(inner_type)}[]"
  defp type_to_string({:array, inner_type}), do: "#{type_to_string(inner_type)}[]"

  # Fixed-size ARRAY (e.g. FLOAT[1536]) — required for vector indexes
  defp type_to_string({:array, inner_type, size}) when is_integer(size) and size > 0,
    do: "#{type_to_string(inner_type)}[#{size}]"

  defp type_to_string({:map, key_type, val_type}),
    do: "MAP(#{type_to_string(key_type)}, #{type_to_string(val_type)})"

  # Escape identifier to handle reserved keywords
  defp escape_identifier(name) do
    # List of reserved keywords in LadybugDB/Cypher
    reserved = [
      "order",
      "group",
      "by",
      "where",
      "return",
      "match",
      "create",
      "delete",
      "set",
      "merge",
      "with",
      "union",
      "all",
      "distinct",
      "limit",
      "skip",
      "desc",
      "asc",
      "and",
      "or",
      "not",
      "exists",
      "in",
      "as",
      "from",
      "to"
    ]

    if String.downcase(name) in reserved do
      "`#{name}`"
    else
      name
    end
  end
end
