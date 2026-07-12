defmodule LadybugEx.Extensions do
  @moduledoc """
  Generic interface for managing LadybugDB extensions.

  LadybugDB provides official extensions that add specialized functionality
  to the database. Extensions must be installed (one-time download) and then
  loaded (per-session activation) before use.

  ## Available Extensions

  - `algo` - Graph algorithms (PageRank, SCC, WCC, Louvain, K-Core)
  - `azure` - Azure Blob Storage and ADLS scanning
  - `delta` - Delta Lake table scanning
  - `duckdb` - DuckDB database integration
  - `fts` - Full-text search using BM25 algorithm
  - `httpfs` - HTTP(S) file operations and remote database attachment
  - `iceberg` - Iceberg table scanning
  - `json` - JSON data scanning and manipulation
  - `llm` - Text embeddings generation via external APIs
  - `neo4j` - Neo4j data migration
  - `postgres` - PostgreSQL database integration
  - `sqlite` - SQLite database integration
  - `unity` - Unity Catalog table scanning
  - `vector` - Vector similarity search with HNSW indexing

  ## Usage

      # Install and load an extension
      {:ok, _} = Extensions.install_and_load(conn, "vector")

      # Check if extension is loaded
      true = Extensions.loaded?(conn, "vector")

      # List all available extensions
      {:ok, extensions} = Extensions.list_available(conn)

      # List loaded extensions
      {:ok, loaded} = Extensions.list_loaded(conn)

  ## Session Scope

  Extensions are scoped to the connection session. You must load extensions
  for each new connection where you want to use them.
  """

  alias LadybugEx.Connection

  @type extension_name :: String.t()
  @type extension_info :: %{String.t() => any()}
  @type error :: {:error, String.t()}

  @doc """
  Install an extension from the official extension server.

  This downloads the extension to the local file system. Installation
  is only needed once per extension, not per session.

  ## Examples

      iex> Extensions.install(conn, "vector")
      :ok

      iex> Extensions.install(conn, "nonexistent")
      {:error, "Extension 'nonexistent' not found"}
  """
  @spec install(Connection.t(), extension_name()) :: :ok | error()
  def install(conn, extension_name) when is_binary(extension_name) do
    case Connection.query(conn, "INSTALL #{extension_name};") do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Install an extension from the official extension server.

  Raises an error if the installation fails.

  ## Examples

      iex> Extensions.install!(conn, "vector")
      :ok
  """
  @spec install!(Connection.t(), extension_name()) :: :ok
  def install!(conn, extension_name) do
    case install(conn, extension_name) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to install extension '#{extension_name}': #{reason}"
    end
  end

  @doc """
  Install an extension from a custom server or file path.

  ## Examples

      iex> Extensions.install_from(conn, "myext", "https://myserver.com/extensions")
      :ok

      iex> Extensions.install_from(conn, "myext", "/path/to/myext.lbug_extension")
      :ok
  """
  @spec install_from(Connection.t(), extension_name(), String.t()) :: :ok | error()
  def install_from(conn, extension_name, source)
      when is_binary(extension_name) and is_binary(source) do
    query =
      if String.contains?(source, "://") do
        "INSTALL #{extension_name} FROM '#{source}';"
      else
        "LOAD EXTENSION '#{source}';"
      end

    case Connection.query(conn, query) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Install an extension from a custom server or file path.

  Raises an error if the installation fails.
  """
  @spec install_from!(Connection.t(), extension_name(), String.t()) :: :ok
  def install_from!(conn, extension_name, source) do
    case install_from(conn, extension_name, source) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "Failed to install extension '#{extension_name}' from '#{source}': #{reason}"
    end
  end

  @doc """
  Load an extension for the current connection session.

  Extensions must be loaded in every new connection where you want to use them.
  The extension must be installed first using `install/2`.

  ## Examples

      iex> Extensions.load(conn, "vector")
      :ok

      iex> Extensions.load(conn, "not_installed")
      {:error, "Extension 'not_installed' is not installed"}
  """
  @spec load(Connection.t(), extension_name()) :: :ok | error()
  def load(conn, extension_name) when is_binary(extension_name) do
    case Connection.query(conn, "LOAD #{extension_name};") do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Load an extension for the current connection session.

  Raises an error if the loading fails.

  ## Examples

      iex> Extensions.load!(conn, "vector")
      :ok
  """
  @spec load!(Connection.t(), extension_name()) :: :ok
  def load!(conn, extension_name) do
    case load(conn, extension_name) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to load extension '#{extension_name}': #{reason}"
    end
  end

  @doc """
  Install and load an extension in one operation.

  Convenience function that installs the extension if needed, then loads it
  for the current connection.

  ## Examples

      iex> Extensions.install_and_load(conn, "vector")
      :ok
  """
  @spec install_and_load(Connection.t(), extension_name()) :: :ok | error()
  def install_and_load(conn, extension_name) when is_binary(extension_name) do
    with :ok <- install(conn, extension_name) do
      load(conn, extension_name)
    end
  end

  @doc """
  Install and load an extension in one operation.

  Raises an error if either operation fails.

  ## Examples

      iex> Extensions.install_and_load!(conn, "vector")
      :ok
  """
  @spec install_and_load!(Connection.t(), extension_name()) :: :ok
  def install_and_load!(conn, extension_name) do
    case install_and_load(conn, extension_name) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "Failed to install and load extension '#{extension_name}': #{reason}"
    end
  end

  @doc """
  Update an extension by re-downloading it from the extension server.

  ## Examples

      iex> Extensions.update(conn, "vector")
      :ok
  """
  @spec update(Connection.t(), extension_name()) :: :ok | error()
  def update(conn, extension_name) when is_binary(extension_name) do
    case Connection.query(conn, "UPDATE #{extension_name};") do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Update an extension by re-downloading it from the extension server.

  Raises an error if the update fails.

  ## Examples

      iex> Extensions.update!(conn, "vector")
      :ok
  """
  @spec update!(Connection.t(), extension_name()) :: :ok
  def update!(conn, extension_name) do
    case update(conn, extension_name) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to update extension '#{extension_name}': #{reason}"
    end
  end

  @doc """
  Uninstall an extension, removing it from the file system.

  ## Examples

      iex> Extensions.uninstall(conn, "vector")
      :ok
  """
  @spec uninstall(Connection.t(), extension_name()) :: :ok | error()
  def uninstall(conn, extension_name) when is_binary(extension_name) do
    case Connection.query(conn, "UNINSTALL #{extension_name};") do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc """
  Uninstall an extension, removing it from the file system.

  Raises an error if the uninstall fails.

  ## Examples

      iex> Extensions.uninstall!(conn, "vector")
      :ok
  """
  @spec uninstall!(Connection.t(), extension_name()) :: :ok
  def uninstall!(conn, extension_name) do
    case uninstall(conn, extension_name) do
      :ok -> :ok
      {:error, reason} -> raise "Failed to uninstall extension '#{extension_name}': #{reason}"
    end
  end

  @doc """
  List all available official extensions.

  Returns a list of extension information including name, description, and version.

  ## Examples

      iex> {:ok, extensions} = Extensions.list_available(conn)
      iex> Enum.find(extensions, &(&1["name"] == "vector"))
      %{"name" => "vector", "description" => "Vector similarity search", ...}
  """
  @spec list_available(Connection.t()) :: {:ok, [extension_info()]} | error()
  def list_available(conn) do
    Connection.query(conn, "CALL SHOW_OFFICIAL_EXTENSIONS() RETURN *;")
  end

  @doc """
  List all available official extensions.

  Raises an error if the query fails.

  ## Examples

      iex> extensions = Extensions.list_available!(conn)
      iex> Enum.find(extensions, &(&1["name"] == "vector"))
      %{"name" => "vector", "description" => "Vector similarity search", ...}
  """
  @spec list_available!(Connection.t()) :: [extension_info()]
  def list_available!(conn) do
    case list_available(conn) do
      {:ok, extensions} -> extensions
      {:error, reason} -> raise "Failed to list available extensions: #{reason}"
    end
  end

  @doc """
  List all loaded extensions in the current connection.

  ## Examples

      iex> {:ok, loaded} = Extensions.list_loaded(conn)
      iex> Enum.map(loaded, &(&1["name"]))
      ["vector", "fts"]
  """
  @spec list_loaded(Connection.t()) :: {:ok, [extension_info()]} | error()
  def list_loaded(conn) do
    Connection.query(conn, "CALL SHOW_LOADED_EXTENSIONS() RETURN *;")
  end

  @doc """
  List all loaded extensions in the current connection.

  Raises an error if the query fails.

  ## Examples

      iex> loaded = Extensions.list_loaded!(conn)
      iex> Enum.map(loaded, &(&1["name"]))
      ["vector", "fts"]
  """
  @spec list_loaded!(Connection.t()) :: [extension_info()]
  def list_loaded!(conn) do
    case list_loaded(conn) do
      {:ok, extensions} -> extensions
      {:error, reason} -> raise "Failed to list loaded extensions: #{reason}"
    end
  end

  @doc """
  Check if an extension is loaded in the current connection.

  ## Examples

      iex> Extensions.loaded?(conn, "vector")
      true

      iex> Extensions.loaded?(conn, "not_loaded")
      false
  """
  @spec loaded?(Connection.t(), extension_name()) :: boolean()
  def loaded?(conn, extension_name) when is_binary(extension_name) do
    case list_loaded(conn) do
      {:ok, extensions} ->
        # show_loaded_extensions() reports the name uppercased under the
        # "extension name" column (e.g. "JSON")
        target = String.downcase(extension_name)

        Enum.any?(extensions, fn ext ->
          String.downcase(ext["extension name"] || "") == target
        end)

      {:error, _} ->
        false
    end
  end

  @doc """
  Ensure an extension is loaded, loading it if necessary.

  This is useful in modules that depend on specific extensions. If the
  extension is already loaded, this is a no-op. If not, it attempts to
  load the extension.

  ## Examples

      iex> Extensions.ensure_loaded(conn, "vector")
      :ok

      iex> Extensions.ensure_loaded(conn, "not_installed")
      {:error, "Extension 'not_installed' is not installed"}
  """
  @spec ensure_loaded(Connection.t(), extension_name()) :: :ok | error()
  def ensure_loaded(conn, extension_name) when is_binary(extension_name) do
    if loaded?(conn, extension_name) do
      :ok
    else
      load(conn, extension_name)
    end
  end

  @doc """
  Ensure an extension is loaded, loading it if necessary.

  Raises an error if the extension cannot be loaded.

  ## Examples

      iex> Extensions.ensure_loaded!(conn, "vector")
      :ok
  """
  @spec ensure_loaded!(Connection.t(), extension_name()) :: :ok
  def ensure_loaded!(conn, extension_name) do
    case ensure_loaded(conn, extension_name) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "Failed to ensure extension '#{extension_name}' is loaded: #{reason}"
    end
  end
end
