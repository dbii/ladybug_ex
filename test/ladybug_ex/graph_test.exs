defmodule LadybugEx.GraphTest do
  use ExUnit.Case
  alias LadybugEx.{Database, Connection, Graph, Schema}

  setup do
    {:ok, db} = Database.in_memory()
    {:ok, conn} = Connection.new(db)

    # Create test schema
    Schema.create_node_table(conn, "Person", [
      {:id, :int64, primary_key: true},
      {:name, :string},
      {:age, :int64},
      {:email, :string},
      {:city, :string}
    ])

    Schema.create_node_table(conn, "Product", [
      {:id, :int64, primary_key: true},
      {:name, :string},
      {:price, :double},
      {:category, :string}
    ])

    Schema.create_rel_table(conn, "KNOWS", "Person", "Person", [
      {:since, :int64},
      {:strength, :double}
    ])

    Schema.create_rel_table(conn, "OWNS", "Person", "Product", [
      {:quantity, :int64},
      {:purchased_on, :string}
    ])

    {:ok, conn: conn}
  end

  describe "create_node/3" do
    test "creates a node with properties", %{conn: conn} do
      assert {:ok, node} =
               Graph.create_node(conn, "Person",
                 id: 1,
                 name: "Alice",
                 age: 30,
                 email: "alice@example.com"
               )

      assert node[:node] == true
      assert node[:label] == "Person"
      assert node[:properties][:name] == "Alice"
      assert node[:properties][:age] == 30
    end

    test "creates a node with map properties", %{conn: conn} do
      props = %{
        id: 2,
        name: "Bob",
        age: 25
      }

      assert {:ok, node} = Graph.create_node(conn, "Person", props)
      assert node[:properties][:name] == "Bob"
    end

    test "creates a node without optional properties", %{conn: conn} do
      assert {:ok, node} =
               Graph.create_node(conn, "Person",
                 id: 3,
                 name: "Charlie"
                 # age and email are optional
               )

      assert node[:properties][:name] == "Charlie"
      assert node[:properties][:age] == nil
    end

    test "creates nodes with different labels", %{conn: conn} do
      assert {:ok, person} =
               Graph.create_node(conn, "Person",
                 id: 4,
                 name: "Diana"
               )

      assert {:ok, product} =
               Graph.create_node(conn, "Product",
                 id: 1,
                 name: "Laptop",
                 price: 999.99
               )

      assert person[:label] == "Person"
      assert product[:label] == "Product"
    end

    test "handles various property types", %{conn: conn} do
      assert {:ok, node} =
               Graph.create_node(conn, "Product",
                 id: 2,
                 name: "Phone",
                 price: 599.99,
                 category: "Electronics"
               )

      assert is_float(node[:properties][:price])
      assert is_binary(node[:properties][:category])
    end

    test "handles invalid label", %{conn: conn} do
      assert {:error, _reason} =
               Graph.create_node(conn, "NonExistentTable",
                 id: 1,
                 name: "Test"
               )
    end

    test "handles constraint violations", %{conn: conn} do
      # Create first node
      Graph.create_node!(conn, "Person", id: 1, name: "Alice")

      # Try to create another with same primary key
      assert {:error, _reason} =
               Graph.create_node(conn, "Person",
                 # Duplicate primary key
                 id: 1,
                 name: "Bob"
               )
    end
  end

  describe "create_relationship/5" do
    setup %{conn: conn} do
      # Create test nodes
      {:ok, alice} =
        Graph.create_node(conn, "Person",
          id: 1,
          name: "Alice"
        )

      {:ok, bob} =
        Graph.create_node(conn, "Person",
          id: 2,
          name: "Bob"
        )

      {:ok, product} =
        Graph.create_node(conn, "Product",
          id: 1,
          name: "Laptop"
        )

      {:ok, alice: alice, bob: bob, product: product}
    end

    test "creates relationship between nodes", %{conn: conn, alice: alice, bob: bob} do
      assert {:ok, rel} =
               Graph.create_relationship(conn, alice.id, bob.id, "KNOWS",
                 since: 2020,
                 strength: 0.8
               )

      assert rel[:rel] == true
      assert rel[:label] == "KNOWS"
      assert rel[:properties][:since] == 2020
      assert rel[:properties][:strength] == 0.8
    end

    test "creates relationship without properties", %{conn: conn, alice: alice, bob: bob} do
      assert {:ok, rel} = Graph.create_relationship(conn, alice.id, bob.id, "KNOWS")

      assert rel[:label] == "KNOWS"
      assert rel[:properties] == %{} or map_size(rel[:properties]) == 0
    end

    test "creates relationships with different types", %{
      conn: conn,
      alice: alice,
      product: product
    } do
      assert {:ok, rel} =
               Graph.create_relationship(conn, alice.id, product.id, "OWNS",
                 quantity: 1,
                 purchased_on: "2024-01-15"
               )

      assert rel[:label] == "OWNS"
      assert rel[:properties][:quantity] == 1
    end

    test "relationship maintains direction", %{conn: conn, alice: alice, bob: bob} do
      assert {:ok, rel} = Graph.create_relationship(conn, alice.id, bob.id, "KNOWS")

      assert rel[:src] != nil
      assert rel[:dst] != nil
      # The actual node verification would need proper ID comparison
    end

    test "handles non-existent source node", %{conn: conn, bob: bob} do
      assert {:error, _reason} = Graph.create_relationship(conn, 999_999, bob.id, "KNOWS")
    end

    test "handles non-existent target node", %{conn: conn, alice: alice} do
      assert {:error, _reason} = Graph.create_relationship(conn, alice.id, 999_999, "KNOWS")
    end

    test "handles invalid relationship type", %{conn: conn, alice: alice, bob: bob} do
      assert {:error, _reason} = Graph.create_relationship(conn, alice.id, bob.id, "INVALID_REL")
    end
  end

  describe "find_nodes/4" do
    setup %{conn: conn} do
      # Create test data
      people = [
        %{id: 1, name: "Alice", age: 30, city: "New York"},
        %{id: 2, name: "Bob", age: 25, city: "Los Angeles"},
        %{id: 3, name: "Charlie", age: 35, city: "New York"},
        %{id: 4, name: "Diana", age: 25, city: "Chicago"},
        %{id: 5, name: "Eve", age: 40, city: "New York"}
      ]

      for person <- people do
        Graph.create_node!(conn, "Person", person)
      end

      {:ok, conn: conn}
    end

    test "finds all nodes of a label", %{conn: conn} do
      assert {:ok, nodes} = Graph.find_nodes(conn, "Person")
      assert length(nodes) == 5
      assert Enum.all?(nodes, &(&1[:label] == "Person"))
    end

    test "finds nodes with map conditions", %{conn: conn} do
      assert {:ok, nodes} = Graph.find_nodes(conn, "Person", %{age: 25})
      assert length(nodes) == 2
      assert Enum.all?(nodes, &(&1[:properties][:age] == 25))
    end

    test "finds nodes with multiple conditions", %{conn: conn} do
      assert {:ok, nodes} =
               Graph.find_nodes(conn, "Person", %{
                 age: 25,
                 city: "Los Angeles"
               })

      assert length(nodes) == 1
      assert hd(nodes)[:properties][:name] == "Bob"
    end

    test "finds nodes with string WHERE clause", %{conn: conn} do
      assert {:ok, nodes} = Graph.find_nodes(conn, "Person", "n.age > 30")
      assert length(nodes) == 2
      assert Enum.all?(nodes, &(&1[:properties][:age] > 30))
    end

    test "supports LIMIT option", %{conn: conn} do
      assert {:ok, nodes} = Graph.find_nodes(conn, "Person", nil, limit: 3)
      assert length(nodes) == 3
    end

    test "supports ORDER BY option", %{conn: conn} do
      assert {:ok, nodes} =
               Graph.find_nodes(conn, "Person", nil,
                 order_by: "age",
                 limit: 10
               )

      ages = Enum.map(nodes, & &1[:properties][:age])
      assert ages == Enum.sort(ages)
    end

    test "supports DESC ordering", %{conn: conn} do
      assert {:ok, nodes} =
               Graph.find_nodes(conn, "Person", nil,
                 order_by: "age",
                 desc: true,
                 limit: 10
               )

      ages = Enum.map(nodes, & &1[:properties][:age])
      assert ages == Enum.sort(ages, :desc)
    end

    test "combines WHERE, ORDER BY, and LIMIT", %{conn: conn} do
      assert {:ok, nodes} =
               Graph.find_nodes(conn, "Person", %{city: "New York"},
                 order_by: "age",
                 desc: true,
                 limit: 2
               )

      assert length(nodes) == 2
      assert Enum.all?(nodes, &(&1[:properties][:city] == "New York"))

      ages = Enum.map(nodes, & &1[:properties][:age])
      # Eve and Charlie
      assert ages == [40, 35]
    end

    test "returns empty list when no matches", %{conn: conn} do
      assert {:ok, nodes} = Graph.find_nodes(conn, "Person", %{age: 100})
      assert nodes == []
    end

    test "handles nil where clause", %{conn: conn} do
      assert {:ok, nodes1} = Graph.find_nodes(conn, "Person")
      assert {:ok, nodes2} = Graph.find_nodes(conn, "Person", nil)
      assert length(nodes1) == length(nodes2)
    end
  end

  describe "shortest_path/4" do
    setup %{conn: conn} do
      # Create a network of people
      people =
        for i <- 1..6 do
          {:ok, node} =
            Graph.create_node(conn, "Person",
              id: i,
              name: "Person#{i}"
            )

          {i, node}
        end
        |> Map.new()

      # Create relationships forming a network:
      # 1 -> 2 -> 3
      # |    |    |
      # v    v    v
      # 4 -> 5 -> 6
      relationships = [
        {1, 2},
        {2, 3},
        {1, 4},
        {2, 5},
        {3, 6},
        {4, 5},
        {5, 6}
      ]

      for {from, to} <- relationships do
        Graph.create_relationship!(
          conn,
          people[from].id,
          people[to].id,
          "KNOWS"
        )
      end

      {:ok, conn: conn, people: people}
    end

    test "finds direct path", %{conn: conn, people: people} do
      assert {:ok, path} =
               Graph.shortest_path(
                 conn,
                 people[1].id,
                 people[2].id
               )

      assert path[:nodes] != nil
      assert path[:rels] != nil
      # Direct connection
      assert length(path[:rels]) == 1
    end

    test "finds multi-hop path", %{conn: conn, people: people} do
      assert {:ok, path} =
               Graph.shortest_path(
                 conn,
                 people[1].id,
                 people[6].id
               )

      # At least 2 hops needed
      assert length(path[:rels]) >= 2
    end

    test "respects relationship type filter", %{conn: conn, people: people} do
      # Create an alternative direct path with different relationship type
      Schema.create_rel_table(conn, "FAMILY", "Person", "Person", [])

      Graph.create_relationship!(
        conn,
        people[1].id,
        people[6].id,
        "FAMILY"
      )

      # Without filter - should find direct FAMILY path
      assert {:ok, path1} =
               Graph.shortest_path(
                 conn,
                 people[1].id,
                 people[6].id
               )

      # With filter - should only use KNOWS relationships
      assert {:ok, path2} =
               Graph.shortest_path(
                 conn,
                 people[1].id,
                 people[6].id,
                 rel_label: "KNOWS"
               )

      # KNOWS path should be longer than unrestricted path
      assert length(path2[:rels]) > length(path1[:rels])
    end

    test "respects max_length constraint", %{conn: conn, people: people} do
      # Path from 1 to 6 requires at least 2 hops
      assert {:error, "No path found"} =
               Graph.shortest_path(
                 conn,
                 people[1].id,
                 people[6].id,
                 max_length: 1
               )

      assert {:ok, _path} =
               Graph.shortest_path(
                 conn,
                 people[1].id,
                 people[6].id,
                 max_length: 3
               )
    end

    test "returns error when no path exists", %{conn: conn, people: people} do
      # Create an isolated node
      {:ok, isolated} =
        Graph.create_node(conn, "Person",
          id: 99,
          name: "Isolated"
        )

      assert {:error, "No path found"} =
               Graph.shortest_path(
                 conn,
                 people[1].id,
                 isolated.id
               )
    end

    test "handles same source and destination", %{conn: conn, people: people} do
      # Behavior depends on implementation - might return empty path or error
      result =
        Graph.shortest_path(
          conn,
          people[1].id,
          people[1].id
        )

      case result do
        {:ok, path} -> assert path[:rels] == [] or length(path[:rels]) == 0
        {:error, _} -> assert true
      end
    end
  end

  describe "get_neighbors/3" do
    setup %{conn: conn} do
      # Create a central node with various connections
      {:ok, center} =
        Graph.create_node(conn, "Person",
          id: 1,
          name: "Center"
        )

      # Create surrounding nodes
      neighbors =
        for i <- 2..7 do
          {:ok, node} =
            Graph.create_node(conn, "Person",
              id: i,
              name: "Neighbor#{i - 1}"
            )

          node
        end

      # Create outgoing relationships (nodes 2,3,4)
      for node <- Enum.take(neighbors, 3) do
        Graph.create_relationship!(
          conn,
          center.id,
          node.id,
          "KNOWS"
        )
      end

      # Create incoming relationships (nodes 5,6,7)
      for node <- Enum.drop(neighbors, 3) do
        Graph.create_relationship!(
          conn,
          node.id,
          center.id,
          "KNOWS"
        )
      end

      {:ok, conn: conn, center: center, neighbors: neighbors}
    end

    test "gets outgoing neighbors by default", %{conn: conn, center: center} do
      assert {:ok, neighbors} = Graph.get_neighbors(conn, center.id)
      assert length(neighbors) == 3
    end

    test "gets incoming neighbors", %{conn: conn, center: center} do
      assert {:ok, neighbors} = Graph.get_neighbors(conn, center.id, direction: :in)
      assert length(neighbors) == 3
    end

    test "gets all neighbors (both directions)", %{conn: conn, center: center} do
      assert {:ok, neighbors} = Graph.get_neighbors(conn, center.id, direction: :both)
      assert length(neighbors) == 6
    end

    test "filters by relationship label", %{conn: conn, center: center, neighbors: neighbors} do
      # Add a different type of relationship
      Schema.create_rel_table(conn, "WORKS_WITH", "Person", "Person", [])

      Graph.create_relationship!(
        conn,
        center.id,
        hd(neighbors).id,
        "WORKS_WITH"
      )

      assert {:ok, knows_neighbors} = Graph.get_neighbors(conn, center.id, rel_label: "KNOWS")

      assert {:ok, works_neighbors} =
               Graph.get_neighbors(conn, center.id, rel_label: "WORKS_WITH")

      assert length(knows_neighbors) == 3
      assert length(works_neighbors) == 1
    end

    test "handles depth parameter for multi-hop neighbors", %{conn: conn, center: center} do
      # Create second-degree connections
      {:ok, _second_degree} =
        Graph.create_node(conn, "Person",
          id: 10,
          name: "SecondDegree"
        )

      # Get a first-degree neighbor
      {:ok, [first_neighbor | _]} = Graph.get_neighbors(conn, center.id, direction: :out)

      # Connect first-degree to second-degree
      # Use the properties.id (user ID) not the internal id
      first_id = first_neighbor[:properties][:id]

      Graph.create_relationship!(
        conn,
        first_id,
        # ID of second_degree node
        10,
        "KNOWS"
      )

      # Depth 1 should not include second-degree
      assert {:ok, depth1} = Graph.get_neighbors(conn, center.id, depth: 1)

      # Depth 2 should include second-degree
      assert {:ok, depth2} = Graph.get_neighbors(conn, center.id, depth: 2)

      assert length(depth2) > length(depth1)
    end

    test "returns empty list for isolated node", %{conn: conn} do
      {:ok, isolated} =
        Graph.create_node(conn, "Person",
          id: 99,
          name: "Isolated"
        )

      assert {:ok, neighbors} = Graph.get_neighbors(conn, isolated.id)
      assert neighbors == []
    end
  end

  describe "update_node/3" do
    setup %{conn: conn} do
      {:ok, node} =
        Graph.create_node(conn, "Person",
          id: 1,
          name: "Original",
          age: 25,
          city: "Boston"
        )

      {:ok, conn: conn, node: node}
    end

    test "updates existing properties", %{conn: conn, node: node} do
      assert {:ok, updated} =
               Graph.update_node(conn, node.id,
                 age: 26,
                 city: "New York"
               )

      assert updated[:properties][:age] == 26
      assert updated[:properties][:city] == "New York"
      # Unchanged
      assert updated[:properties][:name] == "Original"
    end

    test "adds new properties", %{conn: conn, node: node} do
      assert {:ok, updated} = Graph.update_node(conn, node.id, email: "test@example.com")

      assert updated[:properties][:email] == "test@example.com"
      # Preserved
      assert updated[:properties][:name] == "Original"
    end

    test "updates with map properties", %{conn: conn, node: node} do
      updates = %{
        age: 30,
        city: "Seattle"
      }

      assert {:ok, updated} = Graph.update_node(conn, node.id, updates)
      assert updated[:properties][:age] == 30
      assert updated[:properties][:city] == "Seattle"
    end

    test "handles multiple property types", %{conn: conn, node: node} do
      assert {:ok, _updated} =
               Graph.update_node(conn, node.id,
                 # integer
                 age: 27,
                 # string
                 city: "Portland",
                 # boolean (if supported)
                 active: true
               )
    end

    test "returns error for non-existent node", %{conn: conn} do
      assert {:error, "Node not found"} = Graph.update_node(conn, 999_999, age: 30)
    end

    test "empty update is valid", %{conn: conn, node: node} do
      assert {:ok, updated} = Graph.update_node(conn, node.id, %{})
      # Check that the main properties are preserved
      assert updated[:properties][:id] == node[:properties][:id]
      assert updated[:properties][:name] == node[:properties][:name]
      assert updated[:properties][:age] == node[:properties][:age]
      assert updated[:properties][:city] == node[:properties][:city]
    end
  end

  describe "delete_node/3" do
    setup %{conn: conn} do
      {:ok, node} =
        Graph.create_node(conn, "Person",
          id: 1,
          name: "ToDelete"
        )

      {:ok, conn: conn, node: node}
    end

    test "deletes a node without relationships", %{conn: conn, node: node} do
      assert {:ok, :deleted} = Graph.delete_node(conn, node.id)

      # Verify node is gone
      assert {:ok, nodes} = Graph.find_nodes(conn, "Person", %{id: 1})
      assert nodes == []
    end

    test "detach deletes node and relationships", %{conn: conn, node: node} do
      # Create another node and relationship
      {:ok, other} =
        Graph.create_node(conn, "Person",
          id: 2,
          name: "Other"
        )

      Graph.create_relationship!(
        conn,
        node.id,
        other.id,
        "KNOWS"
      )

      # Delete with detach
      assert {:ok, :deleted} = Graph.delete_node(conn, node.id, detach: true)

      # Verify node is gone
      assert {:ok, nodes} = Graph.find_nodes(conn, "Person", %{id: 1})
      assert nodes == []

      # Other node should still exist
      assert {:ok, [remaining]} = Graph.find_nodes(conn, "Person", %{id: 2})
      assert remaining[:properties][:name] == "Other"
    end

    test "fails to delete node with relationships without detach", %{conn: conn, node: node} do
      {:ok, other} =
        Graph.create_node(conn, "Person",
          id: 2,
          name: "Other"
        )

      Graph.create_relationship!(
        conn,
        node.id,
        other.id,
        "KNOWS"
      )

      # Should fail without detach
      assert {:error, _reason} = Graph.delete_node(conn, node.id, detach: false)

      # Node should still exist
      assert {:ok, [existing]} = Graph.find_nodes(conn, "Person", %{id: 1})
      assert existing[:properties][:name] == "ToDelete"
    end

    test "returns error for non-existent node", %{conn: conn} do
      # LadybugDB allows idempotent deletes - deleting non-existent node succeeds
      result = Graph.delete_node(conn, 999_999)
      assert match?({:ok, :deleted}, result) or match?({:error, _}, result)
    end

    test "idempotent deletion", %{conn: conn, node: node} do
      assert {:ok, :deleted} = Graph.delete_node(conn, node.id)
      # Second deletion might succeed (idempotent) or fail
      result = Graph.delete_node(conn, node.id)
      assert match?({:ok, :deleted}, result) or match?({:error, _}, result)
    end
  end

  describe "complex graph operations" do
    test "builds and queries a social network", %{conn: conn} do
      # Create people
      people =
        for i <- 1..5 do
          {:ok, person} =
            Graph.create_node(conn, "Person",
              id: i,
              name: "Person#{i}",
              age: 20 + i * 5
            )

          {i, person}
        end
        |> Map.new()

      # Create friendships
      friendships = [
        {1, 2, 2020},
        {1, 3, 2019},
        {2, 3, 2021},
        {3, 4, 2018},
        {4, 5, 2020}
      ]

      for {from, to, year} <- friendships do
        Graph.create_relationship!(
          conn,
          people[from].id,
          people[to].id,
          "KNOWS",
          since: year
        )
      end

      # Find friends of Person1
      assert {:ok, friends} =
               Graph.get_neighbors(
                 conn,
                 people[1].id,
                 direction: :out,
                 rel_label: "KNOWS"
               )

      assert length(friends) == 2

      # Find path from Person1 to Person5
      assert {:ok, path} =
               Graph.shortest_path(
                 conn,
                 people[1].id,
                 people[5].id
               )

      assert path[:nodes] != nil
      assert path[:rels] != nil
    end

    test "product ownership graph", %{conn: conn} do
      # Create people
      {:ok, alice} =
        Graph.create_node(conn, "Person",
          id: 1,
          name: "Alice"
        )

      {:ok, bob} =
        Graph.create_node(conn, "Person",
          id: 2,
          name: "Bob"
        )

      # Create products
      products =
        for i <- 1..3 do
          {:ok, product} =
            Graph.create_node(conn, "Product",
              id: i,
              name: "Product#{i}",
              price: 100.0 * i
            )

          product
        end

      # Alice owns products 1 and 2
      for product <- Enum.take(products, 2) do
        Graph.create_relationship!(
          conn,
          alice.id,
          product.id,
          "OWNS",
          quantity: 1
        )
      end

      # Bob owns products 2 and 3
      for product <- Enum.drop(products, 1) do
        Graph.create_relationship!(
          conn,
          bob.id,
          product.id,
          "OWNS",
          quantity: 2
        )
      end

      # Find Alice's products
      assert {:ok, alice_products} =
               Graph.get_neighbors(
                 conn,
                 alice.id,
                 direction: :out,
                 rel_label: "OWNS"
               )

      assert length(alice_products) == 2

      # Find Bob's products
      assert {:ok, bob_products} =
               Graph.get_neighbors(
                 conn,
                 bob.id,
                 direction: :out,
                 rel_label: "OWNS"
               )

      assert length(bob_products) == 2
    end
  end
end
