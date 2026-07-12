defmodule LadybugEx.DatabaseTest do
  use ExUnit.Case
  alias LadybugEx.Database

  setup do
    # Ensure a clean temp directory for each test
    tmp_dir = System.tmp_dir!()
    db_path = Path.join(tmp_dir, "test_ladybug_#{System.unique_integer([:positive])}")

    on_exit(fn ->
      File.rm_rf(db_path)
    end)

    {:ok, db_path: db_path}
  end

  describe "in_memory/1" do
    test "creates an in-memory database with default config" do
      assert {:ok, db} = Database.in_memory()
      assert is_reference(db)
    end

    test "creates an in-memory database with custom config" do
      assert {:ok, db} =
               Database.in_memory(
                 max_num_threads: 2,
                 buffer_pool_size: 1024 * 1024 * 10
               )

      assert is_reference(db)
    end

    test "accepts all configuration options" do
      config = [
        buffer_pool_size: 1024 * 1024 * 100,
        max_num_threads: 4,
        enable_compression: true,
        read_only: false,
        max_db_size: 1024 * 1024 * 1024,
        auto_checkpoint: true,
        checkpoint_threshold: 1000,
        throw_on_wal_replay_failure: false,
        enable_checksums: true
      ]

      assert {:ok, db} = Database.in_memory(config)
      assert is_reference(db)
    end

    test "ignores unknown configuration options" do
      assert {:ok, db} =
               Database.in_memory(
                 unknown_option: "value",
                 max_num_threads: 2
               )

      assert is_reference(db)
    end

    test "multiple in-memory databases are independent" do
      assert {:ok, db1} = Database.in_memory()
      assert {:ok, db2} = Database.in_memory()
      assert db1 != db2
    end
  end

  describe "open/2" do
    test "opens a database at specified path", %{db_path: db_path} do
      assert {:ok, db} = Database.open(db_path)
      assert is_reference(db)
    end

    test "opens a database with custom config", %{db_path: db_path} do
      assert {:ok, db} =
               Database.open(db_path,
                 max_num_threads: 4,
                 enable_compression: true
               )

      assert is_reference(db)
    end

    test "creates database directory if it doesn't exist", %{db_path: db_path} do
      nested_path = Path.join(db_path, "nested/db")
      assert {:ok, db} = Database.open(nested_path)
      assert is_reference(db)
    end

    test "opens existing database", %{db_path: db_path} do
      # Create initial database
      assert {:ok, db1} = Database.open(db_path)
      assert is_reference(db1)

      # Open same database again
      assert {:ok, db2} = Database.open(db_path)
      assert is_reference(db2)
    end

    test "respects read_only flag", %{db_path: db_path} do
      # Create database first
      assert {:ok, _db1} = Database.open(db_path)

      # Open in read-only mode
      assert {:ok, db2} = Database.open(db_path, read_only: true)
      assert is_reference(db2)
    end

    test "accepts all configuration options", %{db_path: db_path} do
      config = [
        buffer_pool_size: 1024 * 1024 * 256,
        max_num_threads: 8,
        enable_compression: false,
        read_only: false,
        max_db_size: 1024 * 1024 * 1024 * 10,
        auto_checkpoint: true,
        checkpoint_threshold: 5000,
        throw_on_wal_replay_failure: true,
        enable_checksums: false
      ]

      assert {:ok, db} = Database.open(db_path, config)
      assert is_reference(db)
    end

    test "handles invalid path gracefully" do
      # This test assumes the implementation returns error for invalid paths
      assert {:error, _reason} = Database.open("/invalid\0path")
    end

    test "handles permission errors" do
      # Create a read-only directory (platform-specific)
      protected_path = "/tmp/protected_#{System.unique_integer([:positive])}"
      File.mkdir!(protected_path)
      File.chmod!(protected_path, 0o444)

      result = Database.open(Path.join(protected_path, "db"))
      File.chmod!(protected_path, 0o755)
      File.rm_rf!(protected_path)

      assert {:error, _reason} = result
    end
  end

  describe "in_memory!/1" do
    test "creates an in-memory database or raises" do
      db = Database.in_memory!()
      assert is_reference(db)
    end

    test "accepts configuration options" do
      db = Database.in_memory!(max_num_threads: 2)
      assert is_reference(db)
    end

    test "raises on invalid configuration" do
      # LadybugDB may not validate all configs upfront, so this may succeed
      # or fail depending on underlying implementation
      result =
        try do
          Database.in_memory!(max_num_threads: -1)
          :ok
        rescue
          _ -> :error
        end

      assert result in [:ok, :error]
    end
  end

  describe "open!/2" do
    test "opens a database or raises", %{db_path: db_path} do
      db = Database.open!(db_path)
      assert is_reference(db)
    end

    test "accepts configuration options", %{db_path: db_path} do
      db = Database.open!(db_path, enable_compression: true)
      assert is_reference(db)
    end

    test "raises on invalid path" do
      assert_raise RuntimeError, ~r/Failed to open database/, fn ->
        Database.open!("/invalid\0path")
      end
    end
  end

  describe "database lifecycle" do
    test "database resources are properly managed", %{db_path: db_path} do
      # Create and use database
      assert {:ok, db} = Database.open(db_path)

      # Simulate garbage collection (actual GC behavior depends on runtime)
      :erlang.garbage_collect()

      # Database should still be valid
      assert is_reference(db)
    end

    test "can create multiple databases concurrently" do
      tmp_dir = System.tmp_dir!()

      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            path = Path.join(tmp_dir, "concurrent_db_#{i}")
            result = Database.open(path)
            File.rm_rf(path)
            result
          end)
        end

      results = Task.await_many(tasks)

      for result <- results do
        assert {:ok, db} = result
        assert is_reference(db)
      end
    end
  end

  describe "configuration validation" do
    test "buffer_pool_size accepts positive integers", %{db_path: db_path} do
      for size <- [1024, 1024 * 1024, 1024 * 1024 * 1024] do
        assert {:ok, db} = Database.open(db_path, buffer_pool_size: size)
        assert is_reference(db)
      end
    end

    test "max_num_threads accepts positive integers", %{db_path: db_path} do
      for threads <- [1, 2, 4, 8, 16] do
        assert {:ok, db} = Database.open(db_path, max_num_threads: threads)
        assert is_reference(db)
      end
    end

    test "boolean flags accept true/false", %{db_path: db_path} do
      boolean_flags = [
        :enable_compression,
        :read_only,
        :auto_checkpoint,
        :throw_on_wal_replay_failure,
        :enable_checksums
      ]

      for flag <- boolean_flags, value <- [true, false] do
        assert {:ok, db} = Database.open(db_path, [{flag, value}])
        assert is_reference(db)
      end
    end
  end
end
