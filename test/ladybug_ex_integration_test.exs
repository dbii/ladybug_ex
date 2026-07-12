defmodule LadybugExIntegrationTest do
  use ExUnit.Case
  alias LadybugEx.{Database, Connection, Schema, Graph}

  @moduletag :integration

  describe "end-to-end social network scenario" do
    setup do
      # Create in-memory database
      {:ok, db} =
        Database.in_memory(
          buffer_pool_size: 1024 * 1024 * 10,
          max_num_threads: 2
        )

      {:ok, conn} = Connection.new(db)

      # Create schema
      Schema.create_node_table!(conn, "User", [
        {:id, :int64, primary_key: true},
        {:username, :string},
        {:email, :string},
        {:age, :int64},
        {:joined_date, :date}
      ])

      Schema.create_node_table!(conn, "Post", [
        {:id, :int64, primary_key: true},
        {:content, :string},
        {:created_at, :timestamp},
        {:likes, :int64}
      ])

      Schema.create_rel_table!(conn, "FOLLOWS", "User", "User", [
        {:since, :date}
      ])

      Schema.create_rel_table!(conn, "POSTED", "User", "Post", [
        {:timestamp, :timestamp}
      ])

      Schema.create_rel_table!(conn, "LIKED", "User", "Post", [
        {:timestamp, :timestamp}
      ])

      # Create indexes
      Schema.create_index!(conn, "User", :username)
      Schema.create_index!(conn, "User", :email)
      Schema.create_index!(conn, "Post", :created_at)

      {:ok, conn: conn}
    end

    test "complete social network workflow", %{conn: conn} do
      # Create users
      users =
        for i <- 1..5 do
          {:ok, user} =
            Graph.create_node(conn, "User",
              id: i,
              username: "user#{i}",
              email: "user#{i}@example.com",
              age: 20 + i * 3
            )

          {i, user}
        end
        |> Map.new()

      # Create follow relationships
      Graph.create_relationship!(conn, users[1].id, users[2].id, "FOLLOWS")
      Graph.create_relationship!(conn, users[1].id, users[3].id, "FOLLOWS")
      Graph.create_relationship!(conn, users[2].id, users[3].id, "FOLLOWS")
      Graph.create_relationship!(conn, users[3].id, users[4].id, "FOLLOWS")
      Graph.create_relationship!(conn, users[4].id, users[5].id, "FOLLOWS")

      # Create posts
      posts =
        for i <- 1..3 do
          {:ok, post} =
            Graph.create_node(conn, "Post",
              id: i,
              content: "Post #{i} content",
              likes: i * 10
            )

          {i, post}
        end
        |> Map.new()

      # Users create posts
      Graph.create_relationship!(conn, users[1].id, posts[1].id, "POSTED")
      Graph.create_relationship!(conn, users[2].id, posts[2].id, "POSTED")
      Graph.create_relationship!(conn, users[3].id, posts[3].id, "POSTED")

      # Users like posts
      Graph.create_relationship!(conn, users[2].id, posts[1].id, "LIKED")
      Graph.create_relationship!(conn, users[3].id, posts[1].id, "LIKED")
      Graph.create_relationship!(conn, users[4].id, posts[2].id, "LIKED")

      # Query: Find all users that user1 follows
      {:ok, following} =
        Graph.get_neighbors(conn, users[1].id,
          direction: :out,
          rel_label: "FOLLOWS"
        )

      assert length(following) == 2

      # Query: Find posts by users that user1 follows
      {:ok, results} =
        Connection.query(conn, """
          MATCH (u1:User {id: 1})-[:FOLLOWS]->(u2:User)-[:POSTED]->(p:Post)
          RETURN u2.username AS author, p.content AS content
          ORDER BY u2.id;
        """)

      assert length(results) == 2
      assert hd(results)["author"] == "user2"

      # Query: Find most liked posts
      {:ok, popular_posts} =
        Connection.query(conn, """
          MATCH (p:Post)
          OPTIONAL MATCH (u:User)-[:LIKED]->(p)
          RETURN p.content AS content, count(u) AS like_count
          ORDER BY like_count DESC
          LIMIT 2;
        """)

      assert length(popular_posts) <= 3

      # Query: Find shortest path between users
      {:ok, path} = Graph.shortest_path(conn, users[1].id, users[5].id, rel_label: "FOLLOWS")
      assert path[:nodes] != nil
      assert path[:rels] != nil

      # Transaction: Update post likes count
      Connection.transaction(conn, fn conn ->
        {:ok, _} =
          Connection.query(conn, """
            MATCH (p:Post {id: 1})
            SET p.likes = p.likes + 1;
          """)

        {:ok, _} =
          Connection.query(conn, """
            MATCH (p:Post {id: 2})
            SET p.likes = p.likes + 2;
          """)

        {:ok, :updated}
      end)
    end
  end

  describe "end-to-end e-commerce scenario" do
    setup do
      {:ok, db} = Database.in_memory()
      {:ok, conn} = Connection.new(db)

      # Create schema for e-commerce
      Schema.create_node_table!(conn, "Customer", [
        {:id, :int64, primary_key: true},
        {:name, :string},
        {:email, :string},
        {:credit, :double}
      ])

      Schema.create_node_table!(conn, "Product", [
        {:id, :int64, primary_key: true},
        {:name, :string},
        {:price, :double},
        {:stock, :int64}
      ])

      Schema.create_node_table!(conn, "Order", [
        {:id, :int64, primary_key: true},
        {:order_date, :date},
        {:total, :double},
        {:status, :string}
      ])

      Schema.create_rel_table!(conn, "PURCHASED", "Customer", "Product", [
        {:quantity, :int64},
        {:price, :double},
        {:date, :date}
      ])

      Schema.create_rel_table!(conn, "PLACED", "Customer", "Order", [
        {:timestamp, :timestamp}
      ])

      Schema.create_rel_table!(conn, "CONTAINS", "Order", "Product", [
        {:quantity, :int64},
        {:unit_price, :double}
      ])

      {:ok, conn: conn}
    end

    test "complete purchase workflow", %{conn: conn} do
      # Create customers
      {:ok, customer1} =
        Graph.create_node(conn, "Customer",
          id: 1,
          name: "Alice",
          email: "alice@example.com",
          credit: 1000.0
        )

      {:ok, customer2} =
        Graph.create_node(conn, "Customer",
          id: 2,
          name: "Bob",
          email: "bob@example.com",
          credit: 500.0
        )

      # Create products
      products =
        for i <- 1..5 do
          {:ok, product} =
            Graph.create_node(conn, "Product",
              id: i,
              name: "Product#{i}",
              price: 50.0 * i,
              stock: 100
            )

          {i, product}
        end
        |> Map.new()

      # Create orders
      {:ok, order1} =
        Graph.create_node(conn, "Order",
          id: 1,
          total: 300.0,
          status: "completed"
        )

      {:ok, order2} =
        Graph.create_node(conn, "Order",
          id: 2,
          total: 150.0,
          status: "pending"
        )

      # Connect customers to orders
      Graph.create_relationship!(conn, customer1.id, order1.id, "PLACED")
      Graph.create_relationship!(conn, customer2.id, order2.id, "PLACED")

      # Add products to orders
      Graph.create_relationship!(conn, order1.id, products[1].id, "CONTAINS",
        quantity: 2,
        unit_price: 50.0
      )

      Graph.create_relationship!(conn, order1.id, products[2].id, "CONTAINS",
        quantity: 1,
        unit_price: 100.0
      )

      # Record purchases
      Graph.create_relationship!(conn, customer1.id, products[1].id, "PURCHASED",
        quantity: 2,
        price: 100.0
      )

      # Query: Find all products purchased by a customer
      {:ok, purchased} =
        Connection.query(conn, """
          MATCH (c:Customer {id: 1})-[p:PURCHASED]->(prod:Product)
          RETURN prod.name AS product, p.quantity AS quantity, p.price AS total_paid;
        """)

      assert length(purchased) >= 1
      assert hd(purchased)["quantity"] == 2

      # Query: Calculate total sales per product
      # Note: "Order" is a reserved word in Cypher, need to escape it
      {:ok, sales} =
        Connection.query(conn, """
          MATCH (o:`Order`)-[c:CONTAINS]->(p:Product)
          WHERE o.status = 'completed'
          RETURN p.name AS product, sum(c.quantity) AS units_sold, sum(c.quantity * c.unit_price) AS revenue
          ORDER BY revenue DESC;
        """)

      assert is_list(sales)

      # Transaction: Process a new order
      result =
        Connection.transaction(conn, fn conn ->
          # Check stock
          {:ok, [stock_check]} =
            Connection.query(conn, """
              MATCH (p:Product {id: 3})
              RETURN p.stock AS stock;
            """)

          if stock_check["stock"] >= 2 do
            # Update stock
            {:ok, _} =
              Connection.query(conn, """
                MATCH (p:Product {id: 3})
                SET p.stock = p.stock - 2;
              """)

            # Deduct credit
            {:ok, _} =
              Connection.query(conn, """
                MATCH (c:Customer {id: 1})
                SET c.credit = c.credit - 300.0;
              """)

            {:ok, :order_processed}
          else
            {:error, :insufficient_stock}
          end
        end)

      assert result == {:ok, :order_processed}

      # Verify the transaction results
      {:ok, [customer_check]} =
        Connection.query(conn, """
          MATCH (c:Customer {id: 1})
          RETURN c.credit AS credit;
        """)

      assert customer_check["credit"] == 700.0
    end
  end

  describe "end-to-end knowledge graph scenario" do
    setup do
      {:ok, db} = Database.in_memory()
      {:ok, conn} = Connection.new(db)

      # Create schema for knowledge graph
      Schema.create_node_table!(conn, "Concept", [
        {:id, :int64, primary_key: true},
        {:name, :string},
        {:description, :string},
        {:category, :string}
      ])

      Schema.create_node_table!(conn, "Document", [
        {:id, :int64, primary_key: true},
        {:title, :string},
        {:author, :string},
        {:year, :int64}
      ])

      Schema.create_rel_table!(conn, "RELATED_TO", "Concept", "Concept", [
        {:weight, :double},
        {:type, :string}
      ])

      Schema.create_rel_table!(conn, "MENTIONS", "Document", "Concept", [
        {:frequency, :int64},
        {:relevance, :double}
      ])

      {:ok, conn: conn}
    end

    test "knowledge graph operations", %{conn: conn} do
      # Create concepts
      concepts = [
        %{id: 1, name: "Machine Learning", category: "AI"},
        %{id: 2, name: "Neural Networks", category: "AI"},
        %{id: 3, name: "Deep Learning", category: "AI"},
        %{id: 4, name: "Statistics", category: "Math"},
        %{id: 5, name: "Linear Algebra", category: "Math"}
      ]

      concept_nodes =
        for concept <- concepts do
          {:ok, node} = Graph.create_node(conn, "Concept", concept)
          {concept.id, node}
        end
        |> Map.new()

      # Create concept relationships
      Graph.create_relationship!(conn, concept_nodes[1].id, concept_nodes[2].id, "RELATED_TO",
        weight: 0.9,
        type: "includes"
      )

      Graph.create_relationship!(conn, concept_nodes[2].id, concept_nodes[3].id, "RELATED_TO",
        weight: 0.95,
        type: "subset"
      )

      Graph.create_relationship!(conn, concept_nodes[1].id, concept_nodes[4].id, "RELATED_TO",
        weight: 0.7,
        type: "uses"
      )

      Graph.create_relationship!(conn, concept_nodes[3].id, concept_nodes[5].id, "RELATED_TO",
        weight: 0.8,
        type: "requires"
      )

      # Create documents
      documents = [
        %{id: 1, title: "Introduction to ML", author: "Smith", year: 2020},
        %{id: 2, title: "Deep Learning Fundamentals", author: "Jones", year: 2021},
        %{id: 3, title: "Statistical Methods", author: "Brown", year: 2019}
      ]

      for doc <- documents do
        Graph.create_node!(conn, "Document", doc)
      end

      # Link documents to concepts
      Connection.query!(conn, """
        MATCH (d:Document {id: 1}), (c:Concept {id: 1})
        CREATE (d)-[:MENTIONS {frequency: 50, relevance: 0.9}]->(c);
      """)

      Connection.query!(conn, """
        MATCH (d:Document {id: 2}), (c:Concept {id: 3})
        CREATE (d)-[:MENTIONS {frequency: 100, relevance: 0.95}]->(c);
      """)

      # Query: Find related concepts
      {:ok, related} =
        Connection.query(conn, """
          MATCH (c1:Concept {name: 'Machine Learning'})-[r:RELATED_TO]->(c2:Concept)
          RETURN c2.name AS concept, r.type AS relationship, r.weight AS weight
          ORDER BY r.weight DESC;
        """)

      assert length(related) >= 2

      # Query: Find documents mentioning AI concepts
      {:ok, ai_docs} =
        Connection.query(conn, """
          MATCH (d:Document)-[m:MENTIONS]->(c:Concept)
          WHERE c.category = 'AI'
          RETURN d.title AS document, c.name AS concept, m.relevance AS relevance
          ORDER BY m.relevance DESC;
        """)

      assert length(ai_docs) >= 2

      # Query: Find concept paths
      {:ok, path} =
        Graph.shortest_path(
          conn,
          # Machine Learning
          concept_nodes[1].id,
          # Linear Algebra
          concept_nodes[5].id,
          rel_label: "RELATED_TO"
        )

      assert path[:nodes] != nil

      # Complex query: Concept co-occurrence in documents
      {:ok, cooccurrence} =
        Connection.query(conn, """
          MATCH (d:Document)-[:MENTIONS]->(c1:Concept),
                (d)-[:MENTIONS]->(c2:Concept)
          WHERE id(c1) < id(c2)
          RETURN c1.name AS concept1, c2.name AS concept2, count(d) AS shared_documents
          ORDER BY shared_documents DESC;
        """)

      assert is_list(cooccurrence)
    end
  end

  describe "performance and concurrency" do
    setup do
      {:ok, db} =
        Database.in_memory(
          buffer_pool_size: 1024 * 1024 * 50,
          max_num_threads: 4
        )

      {:ok, conn} = Connection.new(db)

      Schema.create_node_table!(conn, "Node", [
        {:id, :int64, primary_key: true},
        {:value, :int64},
        {:name, :string}
      ])

      Schema.create_rel_table!(conn, "EDGE", "Node", "Node", [
        {:weight, :double}
      ])

      Schema.create_index!(conn, "Node", :value)

      {:ok, conn: conn, db: db}
    end

    test "handles bulk insertions", %{conn: conn} do
      # Prepare statement for bulk insertion
      {:ok, prepared} =
        Connection.prepare(conn, """
          CREATE (:Node {id: $id, value: $value, name: $name});
        """)

      # Insert many nodes
      for i <- 1..100 do
        Connection.execute!(conn, prepared,
          id: i,
          value: rem(i, 10),
          name: "Node#{i}"
        )
      end

      # Verify insertion
      {:ok, [count_result]} =
        Connection.query(conn, """
          MATCH (n:Node)
          RETURN count(n) AS count;
        """)

      assert count_result["count"] == 100

      # Create relationships in bulk
      for i <- 1..99 do
        Connection.query!(conn, """
          MATCH (n1:Node {id: #{i}}), (n2:Node {id: #{i + 1}})
          CREATE (n1)-[:EDGE {weight: #{:rand.uniform()}}]->(n2);
        """)
      end

      # Query with aggregation
      {:ok, aggregates} =
        Connection.query(conn, """
          MATCH (n:Node)
          RETURN n.value AS value, count(n) AS count
          ORDER BY value;
        """)

      assert length(aggregates) == 10
      assert Enum.all?(aggregates, fn row -> row["count"] == 10 end)
    end

    test "concurrent reads work correctly", %{conn: _conn, db: db} do
      # Create multiple connections
      connections =
        for _ <- 1..5 do
          {:ok, conn} = Connection.new(db)
          conn
        end

      # Insert test data
      main_conn = hd(connections)

      for i <- 1..10 do
        Graph.create_node!(main_conn, "Node",
          id: i,
          value: i * 10,
          name: "Concurrent#{i}"
        )
      end

      # Concurrent reads
      tasks =
        for {conn, idx} <- Enum.with_index(connections) do
          Task.async(fn ->
            {:ok, results} =
              Connection.query(conn, """
                MATCH (n:Node)
                WHERE n.value >= #{idx * 20}
                RETURN n.name AS name, n.value AS value
                ORDER BY n.value;
              """)

            {idx, results}
          end)
        end

      results = Task.await_many(tasks, 5000)
      assert length(results) == 5
      assert Enum.all?(results, fn {_, res} -> is_list(res) end)
    end

    test "transactions maintain consistency", %{conn: conn} do
      # Create counter node
      Graph.create_node!(conn, "Node",
        id: 1000,
        value: 0,
        name: "Counter"
      )

      # Successful transaction
      assert {:ok, :incremented} =
               Connection.transaction(conn, fn conn ->
                 {:ok, _} =
                   Connection.query(conn, """
                     MATCH (n:Node {id: 1000})
                     SET n.value = n.value + 1;
                   """)

                 {:ok, :incremented}
               end)

      # Verify increment
      {:ok, [result1]} =
        Connection.query(conn, """
          MATCH (n:Node {id: 1000})
          RETURN n.value AS value;
        """)

      assert result1["value"] == 1

      # Failed transaction (should rollback)
      assert_raise RuntimeError, fn ->
        Connection.transaction(conn, fn conn ->
          Connection.query!(conn, """
            MATCH (n:Node {id: 1000})
            SET n.value = n.value + 10;
          """)

          raise "Simulated failure"
        end)
      end

      # Verify rollback (value should still be 1)
      {:ok, [result2]} =
        Connection.query(conn, """
          MATCH (n:Node {id: 1000})
          RETURN n.value AS value;
        """)

      assert result2["value"] == 1
    end
  end

  describe "prepared statements with complex queries" do
    setup do
      {:ok, db} = Database.in_memory()
      {:ok, conn} = Connection.new(db)

      Schema.create_node_table!(conn, "Entity", [
        {:id, :int64, primary_key: true},
        {:type, :string},
        {:name, :string},
        {:score, :double},
        {:active, :bool}
      ])

      {:ok, conn: conn}
    end

    test "prepared statements with multiple parameters", %{conn: conn} do
      # Create test data
      for i <- 1..20 do
        Graph.create_node!(conn, "Entity",
          id: i,
          type: if(rem(i, 2) == 0, do: "A", else: "B"),
          name: "Entity#{i}",
          score: i * 1.5,
          active: rem(i, 3) != 0
        )
      end

      # Prepare complex query
      {:ok, prepared} =
        Connection.prepare(conn, """
          MATCH (e:Entity)
          WHERE e.type = $type
            AND e.score >= $min_score
            AND e.score <= $max_score
            AND e.active = $active
          RETURN e.name AS name, e.score AS score
          ORDER BY e.score DESC
          LIMIT $limit;
        """)

      # Execute with different parameters
      {:ok, results1} =
        Connection.execute(conn, prepared,
          type: "A",
          min_score: 10.0,
          max_score: 25.0,
          active: true,
          limit: 5
        )

      assert is_list(results1)
      assert Enum.all?(results1, fn r -> r["score"] >= 10.0 and r["score"] <= 25.0 end)

      {:ok, results2} =
        Connection.execute(conn, prepared,
          type: "B",
          min_score: 0.0,
          max_score: 20.0,
          active: true,
          limit: 10
        )

      assert is_list(results2)
      assert Enum.all?(results2, fn r -> r["score"] <= 20.0 end)
    end

    test "prepared statements for updates", %{conn: conn} do
      # Create initial data
      Graph.create_node!(conn, "Entity",
        id: 100,
        type: "Special",
        name: "UpdateTarget",
        score: 50.0,
        active: true
      )

      # Prepare update statement
      {:ok, update_prepared} =
        Connection.prepare(conn, """
          MATCH (e:Entity {id: $id})
          SET e.score = $new_score,
              e.active = $new_active,
              e.name = $new_name
          RETURN e.score AS score, e.active AS active, e.name AS name;
        """)

      # Execute updates
      {:ok, [result1]} =
        Connection.execute(conn, update_prepared,
          id: 100,
          new_score: 75.0,
          new_active: false,
          new_name: "Updated1"
        )

      assert result1["score"] == 75.0
      assert result1["active"] == false
      assert result1["name"] == "Updated1"

      {:ok, [result2]} =
        Connection.execute(conn, update_prepared,
          id: 100,
          new_score: 100.0,
          new_active: true,
          new_name: "Updated2"
        )

      assert result2["score"] == 100.0
      assert result2["active"] == true
      assert result2["name"] == "Updated2"
    end
  end
end
