defmodule LadybugEx.Database do
  @moduledoc """
  Module for managing LadybugDB database instances.

  LadybugDB is an embedded property graph database that supports the Cypher query language.
  This module provides functions to create and manage database instances.
  """

  alias LadybugEx.Native

  @type t :: reference()

  @type config_option ::
          {:buffer_pool_size, non_neg_integer()}
          | {:max_num_threads, non_neg_integer()}
          | {:enable_compression, boolean()}
          | {:read_only, boolean()}
          | {:max_db_size, non_neg_integer()}
          | {:auto_checkpoint, boolean()}
          | {:checkpoint_threshold, integer()}
          | {:throw_on_wal_replay_failure, boolean()}
          | {:enable_checksums, boolean()}

  @type config :: [config_option()]

  @doc """
  Opens a database at the specified path with optional configuration.

  ## Parameters

    * `path` - The file path where the database should be stored
    * `opts` - Optional configuration parameters (see type definition for available options)

  ## Options

    * `:buffer_pool_size` - Size of the buffer pool in bytes
    * `:max_num_threads` - Maximum number of threads to use
    * `:enable_compression` - Whether to enable compression
    * `:read_only` - Open the database in read-only mode
    * `:max_db_size` - Maximum database size in bytes
    * `:auto_checkpoint` - Enable automatic checkpointing
    * `:checkpoint_threshold` - Threshold for automatic checkpointing
    * `:throw_on_wal_replay_failure` - Whether to throw on WAL replay failure
    * `:enable_checksums` - Enable checksums for data integrity

  ## Examples

      iex> {:ok, db} = LadybugEx.Database.open("/tmp/mydb")
      {:ok, #Reference<...>}

      iex> {:ok, db} = LadybugEx.Database.open("/tmp/mydb",
      ...>   buffer_pool_size: 1024 * 1024 * 100,
      ...>   max_num_threads: 4
      ...> )
      {:ok, #Reference<...>}

  ## Returns

    * `{:ok, database}` - Successfully opened database
    * `{:error, reason}` - Error opening database

  """
  @spec open(String.t(), config()) :: {:ok, t()} | {:error, String.t()}
  def open(path, opts \\ []) when is_binary(path) and is_list(opts) do
    Native.open_database(path, opts)
  end

  @doc """
  Creates an in-memory database with optional configuration.

  In-memory databases are useful for testing or temporary data processing.
  All data is lost when the database reference is garbage collected.

  ## Parameters

    * `opts` - Optional configuration parameters (same as `open/2`)

  ## Examples

      iex> {:ok, db} = LadybugEx.Database.in_memory()
      {:ok, #Reference<...>}

      iex> {:ok, db} = LadybugEx.Database.in_memory(max_num_threads: 2)
      {:ok, #Reference<...>}

  ## Returns

    * `{:ok, database}` - Successfully created in-memory database
    * `{:error, reason}` - Error creating database

  """
  @spec in_memory(config()) :: {:ok, t()} | {:error, String.t()}
  def in_memory(opts \\ []) when is_list(opts) do
    Native.in_memory_database(opts)
  end

  @doc """
  Opens a database at the specified path, raising on error.

  Same as `open/2` but raises an exception on error.

  ## Examples

      iex> db = LadybugEx.Database.open!("/tmp/mydb")
      #Reference<...>

  """
  @spec open!(String.t(), config()) :: t()
  def open!(path, opts \\ []) do
    case open(path, opts) do
      {:ok, db} -> db
      {:error, reason} -> raise "Failed to open database: #{reason}"
    end
  end

  @doc """
  Creates an in-memory database, raising on error.

  Same as `in_memory/1` but raises an exception on error.

  ## Examples

      iex> db = LadybugEx.Database.in_memory!()
      #Reference<...>

  """
  @spec in_memory!(config()) :: t()
  def in_memory!(opts \\ []) do
    case in_memory(opts) do
      {:ok, db} -> db
      {:error, reason} -> raise "Failed to create in-memory database: #{reason}"
    end
  end
end
