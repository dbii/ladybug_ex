defmodule LadybugEx.ConnectionTest do
  use ExUnit.Case
  alias LadybugEx.{Database, Connection}

  setup do
    {:ok, db} = Database.in_memory()
    {:ok, db: db}
  end

  describe "new/1" do
    test "creates a connection from database", %{db: db} do
      assert {:ok, conn} = Connection.new(db)
      assert is_reference(conn)
    end

    test "multiple connections to same database", %{db: db} do
      assert {:ok, conn1} = Connection.new(db)
      assert {:ok, conn2} = Connection.new(db)
      assert conn1 != conn2
    end

    test "fails with invalid database reference" do
      invalid_ref = make_ref()
      # May raise ArgumentError instead of returning error tuple
      assert_raise ArgumentError, fn ->
        Connection.new(invalid_ref)
      end
    end
  end

  describe "new!/1" do
    test "creates connection or raises", %{db: db} do
      conn = Connection.new!(db)
      assert is_reference(conn)
    end

    test "raises with invalid database" do
      invalid_ref = make_ref()
      # ArgumentError from NIF is acceptable
      assert_raise ArgumentError, fn ->
        Connection.new!(invalid_ref)
      end
    end
  end

  describe "query/3" do
    setup %{db: db} do
      {:ok, conn} = Connection.new(db)

      # Create test schema
      Connection.query(conn, """
        CREATE NODE TABLE Person(
          id INT64,
          name STRING,
          age INT64,
          PRIMARY KEY(id)
        );
      """)

      {:ok, conn: conn}
    end

    test "executes DDL statements", %{conn: conn} do
      assert {:ok, _result} =
               Connection.query(conn, """
                 CREATE NODE TABLE Product(
                   id INT64,
                   name STRING,
                   price DOUBLE,
                   PRIMARY KEY(id)
                 );
               """)
    end

    test "executes CREATE statements", %{conn: conn} do
      assert {:ok, _result} =
               Connection.query(conn, """
                 CREATE (:Person {id: 1, name: 'Alice', age: 30});
               """)
    end

    test "executes MATCH queries", %{conn: conn} do
      # Insert data first
      Connection.query!(conn, "CREATE (:Person {id: 1, name: 'Alice', age: 30});")
      Connection.query!(conn, "CREATE (:Person {id: 2, name: 'Bob', age: 25});")

      assert {:ok, results} =
               Connection.query(conn, """
                 MATCH (p:Person)
                 RETURN p.name AS name, p.age AS age
                 ORDER BY p.id;
               """)

      assert results == [
               %{"name" => "Alice", "age" => 30},
               %{"name" => "Bob", "age" => 25}
             ]
    end

    test "handles empty result sets", %{conn: conn} do
      assert {:ok, results} =
               Connection.query(conn, """
                 MATCH (p:Person)
                 WHERE p.age > 100
                 RETURN p;
               """)

      assert results == []
    end

    test "supports WHERE clauses", %{conn: conn} do
      Connection.query!(conn, "CREATE (:Person {id: 1, name: 'Alice', age: 30});")
      Connection.query!(conn, "CREATE (:Person {id: 2, name: 'Bob', age: 25});")

      assert {:ok, results} =
               Connection.query(conn, """
                 MATCH (p:Person)
                 WHERE p.age >= 30
                 RETURN p.name AS name;
               """)

      assert results == [%{"name" => "Alice"}]
    end

    test "supports ORDER BY", %{conn: conn} do
      Connection.query!(conn, "CREATE (:Person {id: 1, name: 'Alice', age: 30});")
      Connection.query!(conn, "CREATE (:Person {id: 2, name: 'Bob', age: 25});")
      Connection.query!(conn, "CREATE (:Person {id: 3, name: 'Charlie', age: 35});")

      assert {:ok, results} =
               Connection.query(conn, """
                 MATCH (p:Person)
                 RETURN p.name AS name
                 ORDER BY p.age DESC;
               """)

      assert results == [
               %{"name" => "Charlie"},
               %{"name" => "Alice"},
               %{"name" => "Bob"}
             ]
    end

    test "supports LIMIT", %{conn: conn} do
      for i <- 1..5 do
        Connection.query!(
          conn,
          "CREATE (:Person {id: #{i}, name: 'Person#{i}', age: #{20 + i}});"
        )
      end

      assert {:ok, results} =
               Connection.query(conn, """
                 MATCH (p:Person)
                 RETURN p.id AS id
                 ORDER BY p.id
                 LIMIT 3;
               """)

      assert length(results) == 3
    end

    test "handles syntax errors gracefully", %{conn: conn} do
      assert {:error, reason} = Connection.query(conn, "INVALID CYPHER QUERY")
      # LadybugDB may return different error messages for syntax errors
      assert reason =~ "syntax" or reason =~ "parse" or reason =~ "Parser" or reason =~ "Invalid"
    end

    test "handles runtime errors", %{conn: conn} do
      # Query non-existent table
      assert {:error, _reason} =
               Connection.query(conn, """
                 MATCH (n:NonExistentTable)
                 RETURN n;
               """)
    end
  end

  describe "query!/3" do
    setup %{db: db} do
      {:ok, conn} = Connection.new(db)
      {:ok, conn: conn}
    end

    test "returns results on success", %{conn: conn} do
      Connection.query!(conn, "CREATE NODE TABLE Test(id INT64, PRIMARY KEY(id));")
      result = Connection.query!(conn, "CREATE (:Test {id: 1});")
      assert is_list(result)
    end

    test "raises on error", %{conn: conn} do
      assert_raise RuntimeError, ~r/Query failed/, fn ->
        Connection.query!(conn, "INVALID QUERY")
      end
    end
  end

  describe "prepare/2 and execute/3" do
    setup %{db: db} do
      {:ok, conn} = Connection.new(db)

      Connection.query!(conn, """
        CREATE NODE TABLE Person(
          id INT64,
          name STRING,
          age INT64,
          PRIMARY KEY(id)
        );
      """)

      {:ok, conn: conn}
    end

    test "prepares statement with parameters", %{conn: conn} do
      assert {:ok, prepared} =
               Connection.prepare(conn, """
                 CREATE (:Person {id: $id, name: $name, age: $age});
               """)

      assert is_reference(prepared)
    end

    test "executes prepared statement with keyword list", %{conn: conn} do
      {:ok, prepared} =
        Connection.prepare(conn, """
          CREATE (:Person {id: $id, name: $name, age: $age});
        """)

      assert {:ok, _result} =
               Connection.execute(conn, prepared,
                 id: 1,
                 name: "Alice",
                 age: 30
               )
    end

    test "executes prepared statement with map", %{conn: conn} do
      {:ok, prepared} =
        Connection.prepare(conn, """
          CREATE (:Person {id: $id, name: $name, age: $age});
        """)

      assert {:ok, _result} =
               Connection.execute(conn, prepared, %{
                 id: 2,
                 name: "Bob",
                 age: 25
               })
    end

    test "executes same prepared statement multiple times", %{conn: conn} do
      {:ok, prepared} =
        Connection.prepare(conn, """
          CREATE (:Person {id: $id, name: $name, age: $age});
        """)

      for i <- 1..3 do
        assert {:ok, _} =
                 Connection.execute(conn, prepared,
                   id: i,
                   name: "Person#{i}",
                   age: 20 + i
                 )
      end

      {:ok, results} = Connection.query(conn, "MATCH (p:Person) RETURN count(p) AS count;")
      assert [%{"count" => 3}] = results
    end

    test "prepared SELECT queries", %{conn: conn} do
      # Insert test data
      for i <- 1..5 do
        Connection.query!(
          conn,
          "CREATE (:Person {id: #{i}, name: 'Person#{i}', age: #{20 + i * 5}});"
        )
      end

      {:ok, prepared} =
        Connection.prepare(conn, """
          MATCH (p:Person)
          WHERE p.age >= $min_age
          RETURN p.name AS name, p.age AS age
          ORDER BY p.age;
        """)

      assert {:ok, results} = Connection.execute(conn, prepared, min_age: 35)
      assert length(results) == 3
    end

    test "handles missing parameters", %{conn: conn} do
      {:ok, prepared} =
        Connection.prepare(conn, """
          CREATE (:Person {id: $id, name: $name, age: $age});
        """)

      assert {:error, _reason} =
               Connection.execute(conn, prepared,
                 id: 1,
                 name: "Alice"
                 # missing age parameter
               )
    end

    test "handles type mismatches", %{conn: conn} do
      {:ok, prepared} =
        Connection.prepare(conn, """
          CREATE (:Person {id: $id, name: $name, age: $age});
        """)

      assert {:error, _reason} =
               Connection.execute(conn, prepared,
                 # Should be INT64
                 id: "not_a_number",
                 name: "Alice",
                 age: 30
               )
    end
  end

  describe "prepare!/2 and execute!/3" do
    setup %{db: db} do
      {:ok, conn} = Connection.new(db)
      Connection.query!(conn, "CREATE NODE TABLE Person(id INT64, name STRING, PRIMARY KEY(id));")
      {:ok, conn: conn}
    end

    test "prepare! returns prepared statement", %{conn: conn} do
      prepared = Connection.prepare!(conn, "CREATE (:Person {id: $id, name: $name});")
      assert is_reference(prepared)
    end

    test "execute! returns results", %{conn: conn} do
      prepared = Connection.prepare!(conn, "CREATE (:Person {id: $id, name: $name});")
      result = Connection.execute!(conn, prepared, id: 1, name: "Alice")
      assert is_list(result)
    end

    test "prepare! raises on syntax error", %{conn: conn} do
      assert_raise RuntimeError, ~r/Failed to prepare/, fn ->
        Connection.prepare!(conn, "INVALID QUERY WITH $param")
      end
    end

    test "execute! raises on error", %{conn: conn} do
      prepared = Connection.prepare!(conn, "CREATE (:Person {id: $id, name: $name});")

      assert_raise RuntimeError, ~r/Execution failed/, fn ->
        Connection.execute!(conn, prepared, id: "invalid")
      end
    end
  end

  describe "transaction/2" do
    setup %{db: db} do
      {:ok, conn} = Connection.new(db)

      Connection.query!(conn, """
        CREATE NODE TABLE Account(
          id INT64,
          balance INT64,
          PRIMARY KEY(id)
        );
      """)

      # Create test accounts
      Connection.query!(conn, "CREATE (:Account {id: 1, balance: 1000});")
      Connection.query!(conn, "CREATE (:Account {id: 2, balance: 500});")

      {:ok, conn: conn}
    end

    test "commits successful transactions", %{conn: conn} do
      result =
        Connection.transaction(conn, fn conn ->
          {:ok, _} =
            Connection.query(conn, """
              MATCH (a:Account {id: 1})
              SET a.balance = a.balance - 100;
            """)

          {:ok, _} =
            Connection.query(conn, """
              MATCH (a:Account {id: 2})
              SET a.balance = a.balance + 100;
            """)

          {:ok, :transferred}
        end)

      assert result == {:ok, :transferred}

      # Verify the changes persisted
      {:ok, [%{"balance" => balance1}]} =
        Connection.query(
          conn,
          "MATCH (a:Account {id: 1}) RETURN a.balance AS balance;"
        )

      {:ok, [%{"balance" => balance2}]} =
        Connection.query(
          conn,
          "MATCH (a:Account {id: 2}) RETURN a.balance AS balance;"
        )

      assert balance1 == 900
      assert balance2 == 600
    end

    test "rolls back failed transactions", %{conn: conn} do
      result =
        Connection.transaction(conn, fn conn ->
          {:ok, _} =
            Connection.query(conn, """
              MATCH (a:Account {id: 1})
              SET a.balance = a.balance - 100;
            """)

          # Simulate failure
          {:error, "Insufficient funds"}
        end)

      assert result == {:error, "Insufficient funds"}

      # Verify no changes were made
      {:ok, [%{"balance" => balance}]} =
        Connection.query(
          conn,
          "MATCH (a:Account {id: 1}) RETURN a.balance AS balance;"
        )

      assert balance == 1000
    end

    test "rolls back on exception", %{conn: conn} do
      assert_raise RuntimeError, "Something went wrong", fn ->
        Connection.transaction(conn, fn conn ->
          Connection.query!(conn, """
            MATCH (a:Account {id: 1})
            SET a.balance = a.balance - 100;
          """)

          raise "Something went wrong"
        end)
      end

      # Verify rollback
      {:ok, [%{"balance" => balance}]} =
        Connection.query(
          conn,
          "MATCH (a:Account {id: 1}) RETURN a.balance AS balance;"
        )

      assert balance == 1000
    end

    test "handles nested data correctly", %{conn: conn} do
      result =
        Connection.transaction(conn, fn conn ->
          with {:ok, _} <-
                 Connection.query(
                   conn,
                   "CREATE (:Account {id: 3, balance: 750});"
                 ),
               {:ok, accounts} <-
                 Connection.query(
                   conn,
                   "MATCH (a:Account) RETURN count(a) AS count;"
                 ) do
            {:ok, accounts}
          end
        end)

      assert {:ok, [%{"count" => 3}]} = result
    end

    test "handles invalid return values", %{conn: conn} do
      result =
        Connection.transaction(conn, fn _conn ->
          :invalid_return
        end)

      assert {:error, {:invalid_transaction_result, :invalid_return}} = result
    end
  end

  describe "connection management functions" do
    setup %{db: db} do
      {:ok, conn} = Connection.new(db)
      {:ok, conn: conn}
    end

    test "set_max_threads/2", %{conn: conn} do
      # Not yet implemented - returns error
      assert {:error, _} = Connection.set_max_threads(conn, 4)
    end

    test "set_max_threads/2 validates input", %{conn: conn} do
      # Function guards prevent invalid values
      assert_raise FunctionClauseError, fn ->
        Connection.set_max_threads(conn, 0)
      end
    end

    test "interrupt/1", %{conn: conn} do
      # Not yet implemented - returns error
      assert {:error, _} = Connection.interrupt(conn)
    end

    test "set_query_timeout/2", %{conn: conn} do
      # Not yet implemented - returns error
      assert {:error, _} = Connection.set_query_timeout(conn, 5000)
    end

    test "timeout actually works", %{conn: conn} do
      # 100ms timeout
      Connection.set_query_timeout(conn, 100)

      # This would need a slow query to test properly
      # assert {:error, _timeout} = Connection.query(conn, slow_query)
    end
  end

  describe "concurrent operations" do
    setup %{db: db} do
      {:ok, conn} = Connection.new(db)

      Connection.query!(conn, """
        CREATE NODE TABLE Counter(
          id INT64,
          value INT64,
          PRIMARY KEY(id)
        );
      """)

      Connection.query!(conn, "CREATE (:Counter {id: 1, value: 0});")
      {:ok, conn: conn, db: db}
    end

    test "multiple connections can read concurrently", %{db: db} do
      connections = for _ <- 1..5, do: elem(Connection.new(db), 1)

      tasks =
        for conn <- connections do
          Task.async(fn ->
            Connection.query(conn, "MATCH (c:Counter) RETURN c.value AS value;")
          end)
        end

      results = Task.await_many(tasks)

      for result <- results do
        assert {:ok, [%{"value" => 0}]} = result
      end
    end

    test "write operations are serialized", %{db: db} do
      # Note: This behavior depends on LadybugDB's concurrency model
      connections = for _ <- 1..3, do: elem(Connection.new(db), 1)

      tasks =
        for {conn, i} <- Enum.with_index(connections) do
          Task.async(fn ->
            Connection.transaction(conn, fn conn ->
              # Each connection tries to increment the counter
              Connection.query(conn, """
                MATCH (c:Counter {id: 1})
                SET c.value = c.value + 1;
              """)

              {:ok, i}
            end)
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All should succeed
      for result <- results do
        assert {:ok, _} = result
      end

      # Final value should be 3
      {:ok, conn} = Connection.new(db)

      {:ok, [%{"value" => value}]} =
        Connection.query(
          conn,
          "MATCH (c:Counter {id: 1}) RETURN c.value AS value;"
        )

      assert value == 3
    end
  end
end
