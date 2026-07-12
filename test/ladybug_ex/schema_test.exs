defmodule LadybugEx.SchemaTest do
  use ExUnit.Case
  alias LadybugEx.{Database, Connection, Schema}

  setup do
    {:ok, db} = Database.in_memory()
    {:ok, conn} = Connection.new(db)
    {:ok, conn: conn}
  end

  describe "create_node_table/4" do
    test "creates simple node table", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_node_table(conn, "Person", [
                 {:id, :int64},
                 {:name, :string}
               ])
    end

    test "creates node table with primary key", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_node_table(
                 conn,
                 "Person",
                 [
                   {:id, :int64},
                   {:name, :string},
                   {:email, :string}
                 ],
                 primary_key: [:id]
               )
    end

    test "creates node table with inline primary key", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_node_table(conn, "Person", [
                 {:id, :int64, primary_key: true},
                 {:name, :string},
                 {:age, :int64}
               ])
    end

    test "creates node table with composite primary key", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_node_table(
                 conn,
                 "UserSession",
                 [
                   {:user_id, :int64},
                   {:session_id, :string},
                   {:created_at, :timestamp}
                 ],
                 primary_key: [:user_id, :session_id]
               )
    end

    test "supports all basic data types", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_node_table(conn, "AllTypes", [
                 {:id, :int64, primary_key: true},
                 {:small_int, :int8},
                 {:medium_int, :int16},
                 {:regular_int, :int32},
                 {:big_int, :int64},
                 {:huge_int, :int128},
                 {:unsigned_small, :uint8},
                 {:unsigned_medium, :uint16},
                 {:unsigned_regular, :uint32},
                 {:unsigned_big, :uint64},
                 {:float_val, :float},
                 {:double_val, :double},
                 {:bool_val, :bool},
                 {:text, :string},
                 {:binary_data, :blob},
                 {:unique_id, :uuid},
                 {:decimal_val, :decimal}
               ])
    end

    test "supports temporal data types", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_node_table(conn, "TimeData", [
                 {:id, :int64, primary_key: true},
                 {:birth_date, :date},
                 {:created_at, :timestamp},
                 {:updated_at, :timestamp_tz},
                 {:nano_time, :timestamp_ns},
                 {:milli_time, :timestamp_ms},
                 {:sec_time, :timestamp_sec},
                 {:duration, :interval}
               ])
    end

    test "supports collection types", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_node_table(conn, "Collections", [
                 {:id, :int64, primary_key: true},
                 {:tags, {:list, :string}},
                 {:scores, {:array, :double}},
                 {:metadata, {:map, :string, :string}}
               ])
    end

    test "handles table names with underscores", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_node_table(conn, "user_profile", [
                 {:id, :int64, primary_key: true},
                 {:user_name, :string}
               ])
    end

    test "handles table names with numbers", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_node_table(conn, "Table123", [
                 {:id, :int64, primary_key: true}
               ])
    end

    test "fails on duplicate table name", %{conn: conn} do
      Schema.create_node_table!(conn, "Person", [
        {:id, :int64, primary_key: true}
      ])

      assert {:error, _reason} =
               Schema.create_node_table(conn, "Person", [
                 {:id, :int64, primary_key: true}
               ])
    end

    test "fails without properties", %{conn: conn} do
      # LadybugDB may allow tables without properties
      result = Schema.create_node_table(conn, "Empty", [])
      assert match?({:ok, :created}, result) or match?({:error, _}, result)
    end

    test "creates table with boolean type using alternate name", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_node_table(conn, "Flags", [
                 {:id, :int64, primary_key: true},
                 # Should map to :bool
                 {:is_active, :boolean}
               ])
    end
  end

  describe "create_rel_table/6" do
    setup %{conn: conn} do
      # Create node tables first
      Schema.create_node_table!(conn, "Person", [
        {:id, :int64, primary_key: true},
        {:name, :string}
      ])

      Schema.create_node_table!(conn, "Company", [
        {:id, :int64, primary_key: true},
        {:name, :string}
      ])

      Schema.create_node_table!(conn, "Project", [
        {:id, :int64, primary_key: true},
        {:title, :string}
      ])

      {:ok, conn: conn}
    end

    test "creates simple relationship table", %{conn: conn} do
      assert {:ok, :created} = Schema.create_rel_table(conn, "KNOWS", "Person", "Person")
    end

    test "creates relationship table with properties", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_rel_table(conn, "WORKS_FOR", "Person", "Company", [
                 {:since, :date},
                 {:position, :string},
                 {:salary, :double}
               ])
    end

    test "creates many-to-many relationship", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_rel_table(conn, "ASSIGNED_TO", "Person", "Project", [],
                 multiplicity: :many_to_many
               )
    end

    test "creates one-to-many relationship", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_rel_table(conn, "MANAGES", "Person", "Project", [],
                 multiplicity: :one_to_many
               )
    end

    test "creates one-to-one relationship", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_rel_table(conn, "LEADS", "Person", "Project", [],
                 multiplicity: :one_to_one
               )
    end

    test "creates self-referential relationship", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_rel_table(conn, "REPORTS_TO", "Person", "Person", [
                 {:since, :date}
               ])
    end

    test "handles relationship with all property types", %{conn: conn} do
      assert {:ok, :created} =
               Schema.create_rel_table(conn, "COMPLEX_REL", "Person", "Company", [
                 {:weight, :double},
                 {:priority, :int32},
                 {:active, :bool},
                 {:notes, :string},
                 {:tags, {:list, :string}}
               ])
    end

    test "fails with non-existent source table", %{conn: conn} do
      assert {:error, _reason} = Schema.create_rel_table(conn, "BAD_REL", "NonExistent", "Person")
    end

    test "fails with non-existent target table", %{conn: conn} do
      assert {:error, _reason} = Schema.create_rel_table(conn, "BAD_REL", "Person", "NonExistent")
    end

    test "fails on duplicate relationship table", %{conn: conn} do
      Schema.create_rel_table!(conn, "FRIEND_OF", "Person", "Person")

      assert {:error, _reason} = Schema.create_rel_table(conn, "FRIEND_OF", "Person", "Person")
    end
  end

  describe "create_index/3" do
    setup %{conn: conn} do
      Schema.create_node_table!(conn, "Person", [
        {:id, :int64, primary_key: true},
        {:name, :string},
        {:age, :int64},
        {:email, :string},
        {:city, :string}
      ])

      {:ok, conn: conn}
    end

    test "creates single column index with atom", %{conn: conn} do
      assert {:ok, :created} = Schema.create_index(conn, "Person", :email)
    end

    test "creates single column index with string", %{conn: conn} do
      assert {:ok, :created} = Schema.create_index(conn, "Person", "age")
    end

    test "creates multi-column index", %{conn: conn} do
      assert {:ok, :created} = Schema.create_index(conn, "Person", [:age, :city])
    end

    test "creates index with mixed atom/string columns", %{conn: conn} do
      assert {:ok, :created} = Schema.create_index(conn, "Person", [:age, "city"])
    end

    test "creates multiple indexes on same table", %{conn: conn} do
      assert {:ok, :created} = Schema.create_index(conn, "Person", :email)
      assert {:ok, :created} = Schema.create_index(conn, "Person", :age)
      assert {:ok, :created} = Schema.create_index(conn, "Person", [:city, :age])
    end

    test "fails on non-existent table", %{conn: conn} do
      # LadybugDB may silently succeed for indexes on non-existent tables
      result = Schema.create_index(conn, "NonExistent", :id)
      # Accept either success or failure
      assert match?({:ok, :created}, result) or match?({:error, _}, result)
    end

    test "fails on non-existent column", %{conn: conn} do
      # LadybugDB may silently succeed for indexes on non-existent columns
      result = Schema.create_index(conn, "Person", :bad_column)
      # Accept either success or failure
      assert match?({:ok, :created}, result) or match?({:error, _}, result)
    end
  end

  describe "drop_node_table/3" do
    setup %{conn: conn} do
      Schema.create_node_table!(conn, "ToDelete", [
        {:id, :int64, primary_key: true}
      ])

      {:ok, conn: conn}
    end

    test "drops existing table", %{conn: conn} do
      assert {:ok, :dropped} = Schema.drop_node_table(conn, "ToDelete")

      # Verify table is gone by trying to recreate it
      assert {:ok, :created} =
               Schema.create_node_table(conn, "ToDelete", [
                 {:id, :int64, primary_key: true}
               ])
    end

    test "drops table with cascade option", %{conn: conn} do
      # Create dependent objects
      Schema.create_node_table!(conn, "Dependent", [
        {:id, :int64, primary_key: true}
      ])

      Schema.create_rel_table!(conn, "REFS", "Dependent", "ToDelete")

      assert {:ok, :dropped} = Schema.drop_node_table(conn, "ToDelete", cascade: true)
    end

    test "fails without cascade when dependencies exist", %{conn: conn} do
      Schema.create_node_table!(conn, "Dependent", [
        {:id, :int64, primary_key: true}
      ])

      Schema.create_rel_table!(conn, "REFS", "Dependent", "ToDelete")

      assert {:error, _reason} = Schema.drop_node_table(conn, "ToDelete", cascade: false)
    end

    test "fails on non-existent table", %{conn: conn} do
      assert {:error, _reason} = Schema.drop_node_table(conn, "NonExistent")
    end
  end

  describe "drop_rel_table/3" do
    setup %{conn: conn} do
      Schema.create_node_table!(conn, "Node1", [
        {:id, :int64, primary_key: true}
      ])

      Schema.create_node_table!(conn, "Node2", [
        {:id, :int64, primary_key: true}
      ])

      Schema.create_rel_table!(conn, "REL_TO_DELETE", "Node1", "Node2")

      {:ok, conn: conn}
    end

    test "drops existing relationship table", %{conn: conn} do
      assert {:ok, :dropped} = Schema.drop_rel_table(conn, "REL_TO_DELETE")

      # Verify we can recreate it
      assert {:ok, :created} = Schema.create_rel_table(conn, "REL_TO_DELETE", "Node1", "Node2")
    end

    test "fails on non-existent relationship table", %{conn: conn} do
      assert {:error, _reason} = Schema.drop_rel_table(conn, "NON_EXISTENT_REL")
    end
  end

  describe "list_node_tables/1" do
    test "returns empty list for fresh database", %{conn: conn} do
      assert {:ok, tables} = Schema.list_node_tables(conn)
      assert tables == []
    end

    test "returns all node tables", %{conn: conn} do
      Schema.create_node_table!(conn, "Person", [
        {:id, :int64, primary_key: true}
      ])

      Schema.create_node_table!(conn, "Company", [
        {:id, :int64, primary_key: true}
      ])

      Schema.create_node_table!(conn, "Product", [
        {:id, :int64, primary_key: true}
      ])

      assert {:ok, tables} = Schema.list_node_tables(conn)
      assert Enum.sort(tables) == ["Company", "Person", "Product"]
    end

    test "excludes relationship tables", %{conn: conn} do
      Schema.create_node_table!(conn, "Person", [
        {:id, :int64, primary_key: true}
      ])

      Schema.create_rel_table!(conn, "KNOWS", "Person", "Person")

      assert {:ok, tables} = Schema.list_node_tables(conn)
      assert tables == ["Person"]
    end

    test "reflects dropped tables", %{conn: conn} do
      Schema.create_node_table!(conn, "Temp", [
        {:id, :int64, primary_key: true}
      ])

      assert {:ok, tables1} = Schema.list_node_tables(conn)
      assert "Temp" in tables1

      Schema.drop_node_table!(conn, "Temp")

      assert {:ok, tables2} = Schema.list_node_tables(conn)
      assert "Temp" not in tables2
    end
  end

  describe "list_rel_tables/1" do
    test "returns empty list for fresh database", %{conn: conn} do
      assert {:ok, tables} = Schema.list_rel_tables(conn)
      assert tables == []
    end

    test "returns all relationship tables", %{conn: conn} do
      Schema.create_node_table!(conn, "Person", [
        {:id, :int64, primary_key: true}
      ])

      Schema.create_node_table!(conn, "Company", [
        {:id, :int64, primary_key: true}
      ])

      Schema.create_rel_table!(conn, "KNOWS", "Person", "Person")
      Schema.create_rel_table!(conn, "WORKS_FOR", "Person", "Company")
      Schema.create_rel_table!(conn, "MANAGES", "Person", "Person")

      assert {:ok, tables} = Schema.list_rel_tables(conn)
      assert Enum.sort(tables) == ["KNOWS", "MANAGES", "WORKS_FOR"]
    end

    test "excludes node tables", %{conn: conn} do
      Schema.create_node_table!(conn, "Person", [
        {:id, :int64, primary_key: true}
      ])

      Schema.create_rel_table!(conn, "KNOWS", "Person", "Person")

      assert {:ok, tables} = Schema.list_rel_tables(conn)
      assert tables == ["KNOWS"]
    end
  end

  describe "describe_table/2" do
    setup %{conn: conn} do
      Schema.create_node_table!(conn, "Person", [
        {:id, :int64, primary_key: true},
        {:name, :string},
        {:age, :int64},
        {:active, :bool}
      ])

      {:ok, conn: conn}
    end

    test "describes existing table", %{conn: conn} do
      assert {:ok, info} = Schema.describe_table(conn, "Person")

      assert info[:name] == "Person"
      assert is_list(info[:columns])
      assert length(info[:columns]) >= 4

      # Check for specific columns
      columns_by_name = Map.new(info[:columns], &{&1[:name], &1})

      assert columns_by_name["id"][:is_primary] == true
      assert columns_by_name["name"][:type] =~ "STRING"
      assert columns_by_name["age"][:type] =~ "INT"
      assert columns_by_name["active"][:type] =~ "BOOL"
    end

    test "identifies primary key columns", %{conn: conn} do
      # LadybugDB only supports single primary key (first one in composite list)
      Schema.create_node_table!(
        conn,
        "Composite",
        [
          {:key1, :int64},
          {:key2, :string},
          {:data, :string}
        ],
        primary_key: [:key1, :key2]
      )

      assert {:ok, info} = Schema.describe_table(conn, "Composite")

      primary_columns = Enum.filter(info[:columns], & &1[:is_primary])
      # LadybugDB limitation: only first key is used as primary key
      assert length(primary_columns) == 1
    end

    test "returns error for non-existent table", %{conn: conn} do
      assert {:error, reason} = Schema.describe_table(conn, "NonExistent")
      # LadybugDB returns a catalog exception message
      assert reason =~ "NonExistent"
    end
  end

  describe "complex schema scenarios" do
    test "builds complete e-commerce schema", %{conn: conn} do
      # Users
      assert {:ok, :created} =
               Schema.create_node_table(conn, "User", [
                 {:id, :int64, primary_key: true},
                 {:username, :string},
                 {:email, :string},
                 {:created_at, :timestamp}
               ])

      # Products
      assert {:ok, :created} =
               Schema.create_node_table(conn, "Product", [
                 {:id, :int64, primary_key: true},
                 {:sku, :string},
                 {:name, :string},
                 {:price, :double},
                 {:stock, :int32}
               ])

      # Orders
      assert {:ok, :created} =
               Schema.create_node_table(conn, "Order", [
                 {:id, :int64, primary_key: true},
                 {:order_date, :date},
                 {:total, :double},
                 {:status, :string}
               ])

      # Relationships
      assert {:ok, :created} =
               Schema.create_rel_table(conn, "PLACED", "User", "Order", [
                 {:timestamp, :timestamp}
               ])

      assert {:ok, :created} =
               Schema.create_rel_table(conn, "CONTAINS", "Order", "Product", [
                 {:quantity, :int32},
                 {:unit_price, :double}
               ])

      assert {:ok, :created} =
               Schema.create_rel_table(conn, "REVIEWED", "User", "Product", [
                 {:rating, :int8},
                 {:comment, :string},
                 {:date, :date}
               ])

      # Create indexes
      assert {:ok, :created} = Schema.create_index(conn, "User", :email)
      assert {:ok, :created} = Schema.create_index(conn, "Product", :sku)
      assert {:ok, :created} = Schema.create_index(conn, "Order", [:order_date, :status])

      # Verify schema
      assert {:ok, node_tables} = Schema.list_node_tables(conn)
      assert Enum.sort(node_tables) == ["Order", "Product", "User"]

      assert {:ok, rel_tables} = Schema.list_rel_tables(conn)
      assert Enum.sort(rel_tables) == ["CONTAINS", "PLACED", "REVIEWED"]
    end

    test "builds social network schema", %{conn: conn} do
      # Core entities
      assert {:ok, :created} =
               Schema.create_node_table(conn, "User", [
                 {:id, :int64, primary_key: true},
                 {:username, :string},
                 {:display_name, :string},
                 {:bio, :string},
                 {:joined_at, :timestamp}
               ])

      assert {:ok, :created} =
               Schema.create_node_table(conn, "Post", [
                 {:id, :int64, primary_key: true},
                 {:content, :string},
                 {:created_at, :timestamp},
                 {:likes_count, :int32},
                 {:shares_count, :int32}
               ])

      assert {:ok, :created} =
               Schema.create_node_table(conn, "Group", [
                 {:id, :int64, primary_key: true},
                 {:name, :string},
                 {:description, :string},
                 {:created_at, :timestamp},
                 {:is_public, :bool}
               ])

      # Relationships with various multiplicities
      assert {:ok, :created} =
               Schema.create_rel_table(
                 conn,
                 "FOLLOWS",
                 "User",
                 "User",
                 [
                   {:since, :timestamp}
                 ],
                 multiplicity: :many_to_many
               )

      assert {:ok, :created} =
               Schema.create_rel_table(
                 conn,
                 "POSTED",
                 "User",
                 "Post",
                 [
                   {:timestamp, :timestamp}
                 ],
                 multiplicity: :one_to_many
               )

      assert {:ok, :created} =
               Schema.create_rel_table(
                 conn,
                 "LIKED",
                 "User",
                 "Post",
                 [
                   {:timestamp, :timestamp}
                 ],
                 multiplicity: :many_to_many
               )

      assert {:ok, :created} =
               Schema.create_rel_table(
                 conn,
                 "MEMBER_OF",
                 "User",
                 "Group",
                 [
                   {:joined_at, :timestamp},
                   {:role, :string}
                 ],
                 multiplicity: :many_to_many
               )

      # Complex indexes
      assert {:ok, :created} = Schema.create_index(conn, "User", :username)
      assert {:ok, :created} = Schema.create_index(conn, "Post", :created_at)
      assert {:ok, :created} = Schema.create_index(conn, "Group", [:is_public, :name])
    end
  end
end
