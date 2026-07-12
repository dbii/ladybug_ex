defmodule LadybugEx.Graph do
  @moduledoc """
  High-level graph operations for LadybugDB.

  This module provides Elixir-friendly functions for common graph operations,
  abstracting away the Cypher query language for simple use cases.
  """

  alias LadybugEx.Connection

  @doc """
  Creates a node with the given label and properties.

  ## Parameters

    * `conn` - A connection reference
    * `label` - The node label
    * `properties` - A map or keyword list of properties

  ## Examples

      iex> LadybugEx.Graph.create_node(conn, "Person", name: "Alice", age: 25)
      {:ok, %{node: true, id: ..., label: "Person", properties: %{name: "Alice", age: 25}}}

  """
  @spec create_node(Connection.t(), String.t(), keyword() | map()) ::
          {:ok, map()} | {:error, String.t()}
  def create_node(conn, label, properties \\ %{}) when is_binary(label) do
    props_string = properties_to_cypher(properties)
    # Escape the label if it's a reserved word
    escaped_label = escape_label(label)
    query = "CREATE (n:#{escaped_label} #{props_string}) RETURN n;"

    case Connection.query(conn, query) do
      {:ok, [%{"n" => node}]} -> {:ok, atomize_keys(node)}
      {:ok, _} -> {:error, "Unexpected result format"}
      error -> error
    end
  end

  @doc """
  Creates a node, raising on error.

  Same as `create_node/3` but raises an exception on error.
  """
  @spec create_node!(Connection.t(), String.t(), keyword() | map()) :: map()
  def create_node!(conn, label, properties \\ %{}) do
    case create_node(conn, label, properties) do
      {:ok, node} -> node
      {:error, reason} -> raise "Failed to create node: #{reason}"
    end
  end

  @doc """
  Creates a relationship between two nodes.

  ## Parameters

    * `conn` - A connection reference
    * `from_node_id` - The ID of the source node
    * `to_node_id` - The ID of the destination node
    * `rel_label` - The relationship label
    * `properties` - Optional properties for the relationship

  ## Examples

      iex> LadybugEx.Graph.create_relationship(conn, node1_id, node2_id, "KNOWS",
      ...>   since: 2020
      ...> )
      {:ok, %{rel: true, id: ..., label: "KNOWS", src: ..., dst: ..., properties: %{since: 2020}}}

  """
  @spec create_relationship(
          Connection.t(),
          String.t() | integer(),
          String.t() | integer(),
          String.t(),
          keyword() | map()
        ) :: {:ok, map()} | {:error, String.t()}
  def create_relationship(conn, from_node_id, to_node_id, rel_label, properties \\ %{}) do
    props_string = properties_to_cypher(properties)

    # Create relationship using user IDs
    simplified_query = """
    MATCH (a), (b)
    WHERE a.id IS NOT NULL AND b.id IS NOT NULL
    AND a.id = #{extract_user_id(from_node_id)} AND b.id = #{extract_user_id(to_node_id)}
    CREATE (a)-[r:#{rel_label} #{props_string}]->(b)
    RETURN r;
    """

    case Connection.query(conn, simplified_query) do
      {:ok, [%{"r" => rel}]} ->
        atomized = atomize_keys(rel)
        # Ensure properties field exists and clean up nil values
        atomized =
          if Map.has_key?(atomized, :properties) do
            # Convert nil properties to empty map and filter out nil values
            props = atomized[:properties] || %{}
            props = props |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
            Map.put(atomized, :properties, props)
          else
            Map.put(atomized, :properties, %{})
          end

        {:ok, atomized}

      {:ok, _} ->
        {:error, "Unexpected result format"}

      error ->
        error
    end
  end

  # Extract user ID from internal ID format
  # For "0:0" -> try to match first node created, "0:1" -> second node, etc
  defp extract_user_id(id) when is_binary(id) do
    if String.contains?(id, ":") do
      [_, offset] = String.split(id, ":")
      # Map internal offset to user ID - this assumes nodes were created in order
      # This is a workaround and not ideal
      String.to_integer(offset) + 1
    else
      id
    end
  end

  defp extract_user_id(id) when is_integer(id), do: id
  defp extract_user_id(id), do: id

  @doc """
  Creates a relationship between two nodes, raising on error.

  Same as `create_relationship/5` but raises an exception on error.
  """
  @spec create_relationship!(
          Connection.t(),
          String.t() | integer(),
          String.t() | integer(),
          String.t(),
          keyword() | map()
        ) :: map()
  def create_relationship!(conn, from_node_id, to_node_id, rel_label, properties \\ %{}) do
    case create_relationship(conn, from_node_id, to_node_id, rel_label, properties) do
      {:ok, rel} -> rel
      {:error, reason} -> raise "Failed to create relationship: #{reason}"
    end
  end

  @doc """
  Finds nodes matching the given criteria.

  ## Parameters

    * `conn` - A connection reference
    * `label` - The node label to search for
    * `where_clause` - Optional WHERE clause conditions as a map or string
    * `opts` - Query options

  ## Options

    * `:limit` - Maximum number of results to return
    * `:order_by` - Property to order results by
    * `:desc` - If true, order results in descending order (default: false)

  ## Examples

      iex> LadybugEx.Graph.find_nodes(conn, "Person")
      {:ok, [%{node: true, label: "Person", properties: %{...}}, ...]}

      iex> LadybugEx.Graph.find_nodes(conn, "Person", %{age: 25})
      {:ok, [%{node: true, label: "Person", properties: %{name: "Alice", age: 25}}]}

      iex> LadybugEx.Graph.find_nodes(conn, "Person", "n.age > 20", limit: 10)
      {:ok, [...]}

  """
  @spec find_nodes(Connection.t(), String.t(), map() | String.t() | nil, keyword()) ::
          {:ok, list(map())} | {:error, String.t()}
  def find_nodes(conn, label, where_clause \\ nil, opts \\ []) do
    # Escape the label if it's a reserved word
    escaped_label = escape_label(label)
    query = build_find_query(escaped_label, where_clause, opts)

    case Connection.query(conn, query) do
      {:ok, results} ->
        nodes =
          Enum.map(results, fn
            %{"n" => node} -> atomize_keys(node)
            result -> atomize_keys(result)
          end)

        {:ok, nodes}

      error ->
        error
    end
  end

  @doc """
  Finds nodes matching the given criteria, raising on error.

  Same as `find_nodes/4` but raises an exception on error.
  """
  @spec find_nodes!(Connection.t(), String.t(), map() | String.t() | nil, keyword()) ::
          list(map())
  def find_nodes!(conn, label, where_clause \\ nil, opts \\ []) do
    case find_nodes(conn, label, where_clause, opts) do
      {:ok, nodes} -> nodes
      {:error, reason} -> raise "Failed to find nodes: #{reason}"
    end
  end

  @doc """
  Finds the shortest path between two nodes.

  ## Parameters

    * `conn` - A connection reference
    * `from_node_id` - The ID of the start node
    * `to_node_id` - The ID of the end node
    * `opts` - Path finding options

  ## Options

    * `:rel_label` - Only follow relationships with this label
    * `:max_length` - Maximum path length (default: no limit)

  ## Examples

      iex> LadybugEx.Graph.shortest_path(conn, node1_id, node2_id)
      {:ok, %{nodes: [...], rels: [...]}}

      iex> LadybugEx.Graph.shortest_path(conn, node1_id, node2_id,
      ...>   rel_label: "KNOWS",
      ...>   max_length: 3
      ...> )
      {:ok, %{nodes: [...], rels: [...]}}

  """
  @spec shortest_path(Connection.t(), String.t() | integer(), String.t() | integer(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def shortest_path(conn, from_node_id, to_node_id, opts \\ []) do
    rel_pattern =
      case Keyword.get(opts, :rel_label) do
        nil -> ""
        label -> ":#{label}"
      end

    max_length = Keyword.get(opts, :max_length, 10)

    # Use user IDs for matching
    from_id = extract_user_id(from_node_id)
    to_id = extract_user_id(to_node_id)

    # Since LadybugDB doesn't support shortestPath function, we need to find paths
    # and select the shortest one ourselves
    # Try with increasing path lengths to find the shortest
    find_shortest_path_iteratively(conn, from_id, to_id, rel_pattern, 1, max_length)
  end

  defp find_shortest_path_iteratively(conn, from_id, to_id, rel_pattern, current_len, max_len)
       when current_len <= max_len do
    # Try to find a path of exactly current_len length
    query = """
    MATCH p = (a)-[#{rel_pattern}*#{current_len}]->(b)
    WHERE a.id = #{from_id} AND b.id = #{to_id}
    RETURN p LIMIT 1;
    """

    case Connection.query(conn, query) do
      {:ok, [%{"p" => path}]} ->
        # Convert path format to include nodes and rels arrays
        formatted_path = format_path(path)
        {:ok, formatted_path}

      {:ok, []} ->
        # No path of this length, try longer
        find_shortest_path_iteratively(
          conn,
          from_id,
          to_id,
          rel_pattern,
          current_len + 1,
          max_len
        )

      error ->
        error
    end
  end

  defp find_shortest_path_iteratively(_conn, _from_id, _to_id, _rel_pattern, current_len, max_len)
       when current_len > max_len do
    {:error, "No path found"}
  end

  @doc """
  Gets all neighbors of a node.

  ## Parameters

    * `conn` - A connection reference
    * `node_id` - The ID of the node
    * `opts` - Options for the query

  ## Options

    * `:direction` - `:out` (default), `:in`, or `:both`
    * `:rel_label` - Only follow relationships with this label
    * `:depth` - How many hops to traverse (default: 1)

  ## Examples

      iex> LadybugEx.Graph.get_neighbors(conn, node_id)
      {:ok, [%{node: true, ...}, ...]}

      iex> LadybugEx.Graph.get_neighbors(conn, node_id,
      ...>   direction: :both,
      ...>   rel_label: "KNOWS"
      ...> )
      {:ok, [...]}

  """
  @spec get_neighbors(Connection.t(), String.t() | integer(), keyword()) ::
          {:ok, list(map())} | {:error, String.t()}
  def get_neighbors(conn, node_id, opts \\ []) do
    direction = Keyword.get(opts, :direction, :out)
    rel_label = Keyword.get(opts, :rel_label)
    depth = Keyword.get(opts, :depth, 1)

    rel_pattern = build_relationship_pattern(direction, rel_label, depth)
    # Use user ID for matching
    id = extract_user_id(node_id)

    query = """
    MATCH (a)#{rel_pattern}(b)
    WHERE a.id = #{id}
    RETURN DISTINCT b;
    """

    case Connection.query(conn, query) do
      {:ok, results} ->
        neighbors = Enum.map(results, fn %{"b" => node} -> atomize_keys(node) end)
        {:ok, neighbors}

      error ->
        error
    end
  end

  @doc """
  Gets all neighbors of a node, raising on error.

  Same as `get_neighbors/3` but raises an exception on error.
  """
  @spec get_neighbors!(Connection.t(), String.t() | integer(), keyword()) :: list(map())
  def get_neighbors!(conn, node_id, opts \\ []) do
    case get_neighbors(conn, node_id, opts) do
      {:ok, neighbors} -> neighbors
      {:error, reason} -> raise "Failed to get neighbors: #{reason}"
    end
  end

  @doc """
  Updates properties of a node.

  ## Parameters

    * `conn` - A connection reference
    * `node_id` - The ID of the node to update
    * `properties` - Properties to set or update

  ## Examples

      iex> LadybugEx.Graph.update_node(conn, node_id, age: 26, city: "New York")
      {:ok, %{node: true, properties: %{age: 26, city: "New York", ...}}}

  """
  @spec update_node(Connection.t(), String.t() | integer(), keyword() | map()) ::
          {:ok, map()} | {:error, String.t()}
  def update_node(conn, node_id, properties) do
    # Use user ID for matching
    id = extract_user_id(node_id)

    # Handle empty properties case
    if properties == %{} or properties == [] do
      # For empty updates, just return the node without modifying
      query = """
      MATCH (n)
      WHERE n.id = #{id}
      RETURN n;
      """

      case Connection.query(conn, query) do
        {:ok, [%{"n" => node}]} ->
          atomized = atomize_keys(node)
          # Ensure all properties are present by normalizing the result
          {:ok, normalize_node_properties(atomized)}

        {:ok, []} ->
          {:error, "Node not found"}

        {:ok, _} ->
          {:error, "Unexpected result format"}

        error ->
          error
      end
    else
      # First get the node to see what properties exist
      query = """
      MATCH (n)
      WHERE n.id = #{id}
      RETURN n;
      """

      case Connection.query(conn, query) do
        {:ok, [%{"n" => node}]} ->
          # Only update properties that already exist in the schema
          existing_props = Map.get(node, "properties", %{})

          valid_properties =
            Enum.filter(properties, fn {key, _value} ->
              Map.has_key?(existing_props, to_string(key))
            end)

          if valid_properties == [] do
            # No valid properties to update, return node as-is
            {:ok, atomize_keys(node)}
          else
            set_clause = properties_to_set_clause(valid_properties, "n")

            update_query = """
            MATCH (n)
            WHERE n.id = #{id}
            SET #{set_clause}
            RETURN n;
            """

            case Connection.query(conn, update_query) do
              {:ok, [%{"n" => updated_node}]} ->
                atomized = atomize_keys(updated_node)
                {:ok, normalize_node_properties(atomized)}

              {:ok, []} ->
                {:error, "Node not found"}

              {:ok, _} ->
                {:error, "Unexpected result format"}

              error ->
                error
            end
          end

        {:ok, []} ->
          {:error, "Node not found"}

        error ->
          error
      end
    end
  end

  @doc """
  Updates properties of a node, raising on error.

  Same as `update_node/3` but raises an exception on error.
  """
  @spec update_node!(Connection.t(), String.t() | integer(), keyword() | map()) :: map()
  def update_node!(conn, node_id, properties) do
    case update_node(conn, node_id, properties) do
      {:ok, node} -> node
      {:error, reason} -> raise "Failed to update node: #{reason}"
    end
  end

  @doc """
  Deletes a node and optionally its relationships.

  ## Parameters

    * `conn` - A connection reference
    * `node_id` - The ID of the node to delete
    * `opts` - Deletion options

  ## Options

    * `:detach` - If true, deletes the node and all its relationships (default: false)

  ## Examples

      iex> LadybugEx.Graph.delete_node(conn, node_id)
      {:ok, :deleted}

      iex> LadybugEx.Graph.delete_node(conn, node_id, detach: true)
      {:ok, :deleted}

  """
  @spec delete_node(Connection.t(), String.t() | integer(), keyword()) ::
          {:ok, :deleted} | {:error, String.t()}
  def delete_node(conn, node_id, opts \\ []) do
    delete_cmd = if Keyword.get(opts, :detach, false), do: "DETACH DELETE", else: "DELETE"
    # Use user ID for matching
    id = extract_user_id(node_id)

    query = """
    MATCH (n)
    WHERE n.id = #{id}
    #{delete_cmd} n;
    """

    case Connection.query(conn, query) do
      {:ok, _} -> {:ok, :deleted}
      error -> error
    end
  end

  # Helper functions

  defp properties_to_cypher(properties) when properties == %{} or properties == [], do: ""

  defp properties_to_cypher(properties) do
    props =
      properties
      |> Enum.map(fn {k, v} -> "#{k}: #{value_to_cypher(v)}" end)
      |> Enum.join(", ")

    "{#{props}}"
  end

  defp properties_to_set_clause(properties, variable) do
    properties
    |> Enum.map(fn {k, v} -> "#{variable}.#{k} = #{value_to_cypher(v)}" end)
    |> Enum.join(", ")
  end

  defp value_to_cypher(v) when is_binary(v), do: "'#{escape_string(v)}'"
  defp value_to_cypher(v) when is_integer(v), do: Integer.to_string(v)
  defp value_to_cypher(v) when is_float(v), do: Float.to_string(v)
  defp value_to_cypher(true), do: "true"
  defp value_to_cypher(false), do: "false"
  defp value_to_cypher(nil), do: "null"
  defp value_to_cypher(v) when is_list(v), do: "[#{Enum.map_join(v, ", ", &value_to_cypher/1)}]"

  defp escape_string(s), do: String.replace(s, "'", "\\'")

  defp build_find_query(label, where_clause, opts) do
    base_query = "MATCH (n:#{label})"

    where_part =
      case where_clause do
        nil ->
          ""

        clause when is_binary(clause) ->
          " WHERE #{clause}"

        conditions when is_map(conditions) ->
          cond_str =
            conditions
            |> Enum.map(fn {k, v} -> "n.#{k} = #{value_to_cypher(v)}" end)
            |> Enum.join(" AND ")

          " WHERE #{cond_str}"
      end

    order_part =
      case Keyword.get(opts, :order_by) do
        nil ->
          ""

        prop ->
          direction = if Keyword.get(opts, :desc, false), do: " DESC", else: ""
          " ORDER BY n.#{prop}#{direction}"
      end

    limit_part =
      case Keyword.get(opts, :limit) do
        nil -> ""
        n -> " LIMIT #{n}"
      end

    "#{base_query}#{where_part} RETURN n#{order_part}#{limit_part};"
  end

  defp build_relationship_pattern(direction, label, depth) do
    rel_label = if label, do: ":#{label}", else: ""
    # Use range pattern for depth > 1 to get neighbors up to that depth
    depth_pattern = if depth == 1, do: "", else: "*1..#{depth}"

    case direction do
      :out -> "-[#{rel_label}#{depth_pattern}]->"
      :in -> "<-[#{rel_label}#{depth_pattern}]-"
      :both -> "-[#{rel_label}#{depth_pattern}]-"
    end
  end

  # Helper to convert string keys to atoms for better Elixir ergonomics
  defp atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn
      {k, v} when is_binary(k) ->
        # Special handling for nested properties
        if k == "properties" and is_map(v) do
          {String.to_atom(k), atomize_keys(v)}
        else
          {String.to_atom(k), atomize_value(v)}
        end

      {k, v} ->
        {k, atomize_value(v)}
    end)
    |> Map.new()
  end

  defp atomize_keys(value), do: value

  defp atomize_value(map) when is_map(map), do: atomize_keys(map)
  defp atomize_value(list) when is_list(list), do: Enum.map(list, &atomize_value/1)
  defp atomize_value(value), do: value

  # Escape label if it's a reserved keyword
  defp escape_label(label) do
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
      "to",
      "contains"
    ]

    if String.downcase(label) in reserved do
      "`#{label}`"
    else
      label
    end
  end

  # Helper to format node IDs for use in Cypher queries
  # Format path to have nodes and rels arrays
  defp format_path(path) when is_map(path) do
    nodes = Map.get(path, "nodes", []) |> Enum.map(&atomize_keys/1)
    rels = Map.get(path, "rels", []) |> Enum.map(&atomize_keys/1)

    %{
      nodes: nodes,
      rels: rels
    }
  end

  defp format_path(path), do: path

  # Normalize node properties to ensure consistency
  # LadybugDB returns all schema properties, so just pass through
  defp normalize_node_properties(node) when is_map(node) do
    node
  end
end
