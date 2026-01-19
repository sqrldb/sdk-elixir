defmodule SquirrelDBTest do
  use ExUnit.Case, async: false

  @test_url System.get_env("SQUIRRELDB_URL", "localhost:8080")

  setup do
    {:ok, client} = SquirrelDB.connect(@test_url)
    on_exit(fn -> SquirrelDB.close(client) end)
    %{client: client}
  end

  describe "connection" do
    test "connect without prefix" do
      {:ok, client} = SquirrelDB.connect(@test_url)
      assert :ok = SquirrelDB.ping(client)
      SquirrelDB.close(client)
    end

    test "connect with ws:// prefix" do
      {:ok, client} = SquirrelDB.connect("ws://#{@test_url}")
      assert :ok = SquirrelDB.ping(client)
      SquirrelDB.close(client)
    end

    test "ping", %{client: client} do
      assert :ok = SquirrelDB.ping(client)
    end
  end

  describe "CRUD operations" do
    test "insert document", %{client: client} do
      {:ok, doc} = SquirrelDB.insert(client, "ex_test_users", %{name: "Alice", age: 30})

      assert %SquirrelDB.Document{} = doc
      assert doc.id != nil
      assert doc.collection == "ex_test_users"
      assert doc.data == %{"name" => "Alice", "age" => 30}
      assert doc.created_at != nil
      assert doc.updated_at != nil
    end

    test "query documents", %{client: client} do
      # Insert a document first
      {:ok, _} = SquirrelDB.insert(client, "ex_test_query", %{name: "Bob", age: 25})

      {:ok, docs} = SquirrelDB.query(client, ~s|db.table("ex_test_query").run()|)

      assert is_list(docs)
      assert length(docs) > 0
      assert Enum.all?(docs, &match?(%SquirrelDB.Document{}, &1))
    end

    test "update document", %{client: client} do
      {:ok, inserted} = SquirrelDB.insert(client, "ex_test_update", %{name: "Charlie", age: 35})

      {:ok, updated} =
        SquirrelDB.update(client, "ex_test_update", inserted.id, %{name: "Charlie", age: 36})

      assert updated.id == inserted.id
      assert updated.data == %{"name" => "Charlie", "age" => 36}
    end

    test "delete document", %{client: client} do
      {:ok, inserted} = SquirrelDB.insert(client, "ex_test_delete", %{name: "Dave", age: 40})
      {:ok, deleted} = SquirrelDB.delete(client, "ex_test_delete", inserted.id)

      assert deleted.id == inserted.id
    end

    test "list collections", %{client: client} do
      # Ensure at least one collection exists
      {:ok, _} = SquirrelDB.insert(client, "ex_test_list", %{test: true})

      {:ok, collections} = SquirrelDB.list_collections(client)

      assert is_list(collections)
      assert length(collections) > 0
      assert Enum.all?(collections, &is_binary/1)
    end
  end

  describe "subscriptions" do
    test "subscribe and unsubscribe", %{client: client} do
      test_pid = self()

      callback = fn change ->
        send(test_pid, {:change, change})
      end

      {:ok, :subscribed} =
        SquirrelDB.subscribe(client, ~s|db.table("ex_test_sub").changes()|, callback)

      # Insert a document to trigger a change
      {:ok, _} = SquirrelDB.insert(client, "ex_test_sub", %{name: "Eve", age: 28})

      # Wait for change to arrive
      assert_receive {:change, %SquirrelDB.ChangeEvent{}}, 1000
    end
  end

  describe "errors" do
    test "invalid query returns error", %{client: client} do
      assert {:error, _reason} = SquirrelDB.query(client, "invalid query syntax")
    end
  end
end

defmodule SquirrelDB.TypesTest do
  use ExUnit.Case, async: true

  describe "Document" do
    test "from_map creates document" do
      data = %{
        "id" => "123",
        "collection" => "users",
        "data" => %{"name" => "Test"},
        "created_at" => "2024-01-01T00:00:00Z",
        "updated_at" => "2024-01-01T00:00:00Z"
      }

      doc = SquirrelDB.Document.from_map(data)

      assert doc.id == "123"
      assert doc.collection == "users"
      assert doc.data == %{"name" => "Test"}
    end
  end

  describe "ChangeEvent" do
    test "from_map handles initial" do
      data = %{
        "type" => "initial",
        "document" => %{
          "id" => "123",
          "collection" => "users",
          "data" => %{"name" => "Test"},
          "created_at" => "2024-01-01T00:00:00Z",
          "updated_at" => "2024-01-01T00:00:00Z"
        }
      }

      event = SquirrelDB.ChangeEvent.from_map(data)

      assert event.type == :initial
      assert event.document.id == "123"
    end

    test "from_map handles insert" do
      data = %{
        "type" => "insert",
        "new" => %{
          "id" => "123",
          "collection" => "users",
          "data" => %{"name" => "Test"},
          "created_at" => "2024-01-01T00:00:00Z",
          "updated_at" => "2024-01-01T00:00:00Z"
        }
      }

      event = SquirrelDB.ChangeEvent.from_map(data)

      assert event.type == :insert
      assert event.new != nil
    end

    test "from_map handles update" do
      data = %{
        "type" => "update",
        "old" => %{"name" => "Old"},
        "new" => %{
          "id" => "123",
          "collection" => "users",
          "data" => %{"name" => "New"},
          "created_at" => "2024-01-01T00:00:00Z",
          "updated_at" => "2024-01-01T00:00:00Z"
        }
      }

      event = SquirrelDB.ChangeEvent.from_map(data)

      assert event.type == :update
      assert event.old == %{"name" => "Old"}
      assert event.new != nil
    end

    test "from_map handles delete" do
      data = %{
        "type" => "delete",
        "old" => %{
          "id" => "123",
          "collection" => "users",
          "data" => %{"name" => "Test"},
          "created_at" => "2024-01-01T00:00:00Z",
          "updated_at" => "2024-01-01T00:00:00Z"
        }
      }

      event = SquirrelDB.ChangeEvent.from_map(data)

      assert event.type == :delete
      assert event.old != nil
    end
  end
end
