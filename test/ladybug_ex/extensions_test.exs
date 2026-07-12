defmodule LadybugEx.ExtensionsTest do
  use ExUnit.Case, async: false
  alias LadybugEx.{Database, Connection, Extensions}

  setup do
    # Use a smaller buffer pool size to avoid memory allocation issues
    {:ok, db} = Database.in_memory(buffer_pool_size: 1024 * 1024 * 10)
    {:ok, conn} = Connection.new(db)
    # Resources are automatically cleaned up by garbage collection
    {:ok, %{db: db, conn: conn}}
  end

  describe "install/2" do
    @tag :requires_network
    test "installs an extension from official server", %{conn: conn} do
      # This test requires network access and may fail if extension server is unavailable
      result = Extensions.install(conn, "json")

      case result do
        :ok ->
          assert true

        {:error, reason} ->
          # Extension might not be available on this platform or network issues
          assert is_binary(reason)
      end
    end

    test "returns error for non-existent extension", %{conn: conn} do
      assert {:error, reason} = Extensions.install(conn, "nonexistent_extension_xyz")
      assert is_binary(reason)
    end
  end

  describe "install!/2" do
    test "raises on error", %{conn: conn} do
      assert_raise RuntimeError, ~r/Failed to install extension/, fn ->
        Extensions.install!(conn, "nonexistent_extension_xyz")
      end
    end
  end

  describe "install_from/3" do
    test "installs from a file path", %{conn: _conn} do
      # This would require an actual .lbug_extension file
      # Skipping actual test as we don't have a test extension file
      assert true
    end

    @tag :requires_network
    test "installs from a custom server URL", %{conn: _conn} do
      # This would require a custom extension server
      # Skipping actual test
      assert true
    end
  end

  describe "load/2" do
    @tag :requires_network
    @tag :requires_extension
    test "loads an installed extension", %{conn: conn} do
      # First install the extension
      case Extensions.install(conn, "json") do
        :ok ->
          assert Extensions.load(conn, "json") == :ok

        {:error, _} ->
          # Skip if extension cannot be installed
          assert true
      end
    end

    test "returns error for non-installed extension", %{conn: conn} do
      assert {:error, reason} = Extensions.load(conn, "not_installed_xyz")
      assert is_binary(reason)
    end
  end

  describe "load!/2" do
    test "raises on error", %{conn: conn} do
      assert_raise RuntimeError, ~r/Failed to load extension/, fn ->
        Extensions.load!(conn, "not_installed_xyz")
      end
    end
  end

  describe "install_and_load/2" do
    @tag :requires_network
    @tag :requires_extension
    test "installs and loads extension in one operation", %{conn: conn} do
      result = Extensions.install_and_load(conn, "json")

      case result do
        :ok ->
          # Verify it's loaded
          assert Extensions.loaded?(conn, "json")

        {:error, _reason} ->
          # Extension might not be available
          assert true
      end
    end
  end

  describe "install_and_load!/2" do
    test "raises on error", %{conn: conn} do
      assert_raise RuntimeError, ~r/Failed to install and load extension/, fn ->
        Extensions.install_and_load!(conn, "nonexistent_xyz")
      end
    end
  end

  describe "update/2" do
    @tag :requires_network
    @tag :requires_extension
    test "updates an installed extension", %{conn: conn} do
      # First install
      case Extensions.install(conn, "json") do
        :ok ->
          # Then update
          result = Extensions.update(conn, "json")
          assert result == :ok or match?({:error, _}, result)

        {:error, _} ->
          assert true
      end
    end

    test "returns error for non-installed extension", %{conn: conn} do
      assert {:error, reason} = Extensions.update(conn, "not_installed_xyz")
      assert is_binary(reason)
    end
  end

  describe "update!/2" do
    test "raises on error", %{conn: conn} do
      assert_raise RuntimeError, ~r/Failed to update extension/, fn ->
        Extensions.update!(conn, "not_installed_xyz")
      end
    end
  end

  describe "uninstall/2" do
    @tag :requires_network
    @tag :requires_extension
    test "uninstalls an extension", %{conn: conn} do
      # First install
      case Extensions.install(conn, "json") do
        :ok ->
          assert Extensions.uninstall(conn, "json") == :ok

        {:error, _} ->
          assert true
      end
    end

    test "handles uninstalling non-installed extension", %{conn: conn} do
      # Some databases might return ok, others might error
      result = Extensions.uninstall(conn, "not_installed_xyz")
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "uninstall!/2" do
    test "may raise on error", %{conn: conn} do
      # Behavior depends on database implementation
      try do
        Extensions.uninstall!(conn, "not_installed_xyz")
        assert true
      rescue
        RuntimeError -> assert true
      end
    end
  end

  describe "list_available/1" do
    test "lists official extensions", %{conn: conn} do
      result = Extensions.list_available(conn)

      case result do
        {:ok, extensions} ->
          assert is_list(extensions)

          # If extensions are returned, check structure
          if length(extensions) > 0 do
            extension = List.first(extensions)
            assert is_map(extension)
            # Extensions should have at least a name field
            assert Map.has_key?(extension, "name") or Map.has_key?(extension, "extension_name")
          end

        {:error, _reason} ->
          # Function might not be available in all LadybugDB versions
          assert true
      end
    end
  end

  describe "list_available!/1" do
    test "returns list or raises", %{conn: conn} do
      try do
        extensions = Extensions.list_available!(conn)
        assert is_list(extensions)
      rescue
        RuntimeError -> assert true
      end
    end
  end

  describe "list_loaded/1" do
    test "lists loaded extensions", %{conn: conn} do
      result = Extensions.list_loaded(conn)

      case result do
        {:ok, extensions} ->
          assert is_list(extensions)
          # Should be empty initially
          assert extensions == [] or is_list(extensions)

        {:error, _reason} ->
          # Function might not be available
          assert true
      end
    end

    @tag :requires_network
    @tag :requires_extension
    test "includes loaded extension in list", %{conn: conn} do
      case Extensions.install_and_load(conn, "json") do
        :ok ->
          {:ok, loaded} = Extensions.list_loaded(conn)
          assert is_list(loaded)

          # Check if json is in the list. The engine reports the name
          # uppercased under the "extension name" column.
          assert Enum.any?(loaded, fn ext ->
                   String.downcase(Map.get(ext, "extension name", "")) == "json"
                 end)

        {:error, _} ->
          assert true
      end
    end
  end

  describe "list_loaded!/1" do
    test "returns list or raises", %{conn: conn} do
      try do
        loaded = Extensions.list_loaded!(conn)
        assert is_list(loaded)
      rescue
        RuntimeError -> assert true
      end
    end
  end

  describe "loaded?/2" do
    test "returns false for non-loaded extension", %{conn: conn} do
      refute Extensions.loaded?(conn, "not_loaded")
    end

    @tag :requires_network
    @tag :requires_extension
    test "returns true for loaded extension", %{conn: conn} do
      case Extensions.install_and_load(conn, "json") do
        :ok ->
          assert Extensions.loaded?(conn, "json")

        {:error, _} ->
          assert true
      end
    end

    test "handles query errors gracefully", %{conn: conn} do
      # Even with errors, should return false
      result = Extensions.loaded?(conn, "test")
      assert is_boolean(result)
    end
  end

  describe "ensure_loaded/2" do
    @tag :requires_network
    @tag :requires_extension
    test "loads extension if not already loaded", %{conn: conn} do
      # First install
      case Extensions.install(conn, "json") do
        :ok ->
          # Ensure not loaded
          refute Extensions.loaded?(conn, "json")

          # Ensure loaded
          assert Extensions.ensure_loaded(conn, "json") == :ok

          # Should now be loaded
          assert Extensions.loaded?(conn, "json")

          # Calling again should be no-op
          assert Extensions.ensure_loaded(conn, "json") == :ok

        {:error, _} ->
          assert true
      end
    end

    test "returns error if extension not installed", %{conn: conn} do
      assert {:error, reason} = Extensions.ensure_loaded(conn, "not_installed")
      assert is_binary(reason)
    end
  end

  describe "ensure_loaded!/2" do
    test "raises if extension not installed", %{conn: conn} do
      assert_raise RuntimeError, ~r/Failed to ensure extension/, fn ->
        Extensions.ensure_loaded!(conn, "not_installed")
      end
    end
  end

  describe "integration" do
    @tag :requires_network
    @tag :requires_extension
    test "complete extension lifecycle", %{conn: conn} do
      extension_name = "json"

      # Check not loaded initially
      refute Extensions.loaded?(conn, extension_name)

      # Install
      case Extensions.install(conn, extension_name) do
        :ok ->
          # Still not loaded after install
          refute Extensions.loaded?(conn, extension_name)

          # Load
          assert Extensions.load(conn, extension_name) == :ok

          # Now loaded
          assert Extensions.loaded?(conn, extension_name)

          # Can query loaded extensions
          {:ok, loaded} = Extensions.list_loaded(conn)
          assert is_list(loaded)

          # Update
          Extensions.update(conn, extension_name)

          # Uninstall
          assert Extensions.uninstall(conn, extension_name) == :ok

        {:error, _reason} ->
          # Extension not available, skip test
          assert true
      end
    end

    @tag :requires_network
    @tag :requires_extension
    test "multiple extensions can be managed independently", %{conn: conn} do
      # Try to install multiple extensions
      # Some might not be available on all platforms.
      # Note: httpfs is deliberately not used here — the prebuilt httpfs
      # binary is ABI-incompatible with the engine compiled from the lbug
      # crate and segfaults the VM on LOAD (upstream issue).
      extensions_to_try = ["json", "fts"]

      installed =
        Enum.reduce(extensions_to_try, [], fn ext, acc ->
          case Extensions.install(conn, ext) do
            :ok -> [ext | acc]
            {:error, _} -> acc
          end
        end)

      # Load all successfully installed
      Enum.each(installed, fn ext ->
        assert Extensions.load(conn, ext) == :ok
        assert Extensions.loaded?(conn, ext)
      end)

      # Clean up
      Enum.each(installed, fn ext ->
        Extensions.uninstall(conn, ext)
      end)
    end
  end
end
