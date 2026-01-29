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
      assert doc.created_at == "2024-01-01T00:00:00Z"
      assert doc.updated_at == "2024-01-01T00:00:00Z"
    end

    test "document has correct fields" do
      doc = %SquirrelDB.Document{
        id: "test-id",
        collection: "test-collection",
        data: %{"foo" => "bar"},
        created_at: "2024-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z"
      }

      assert is_binary(doc.id)
      assert is_binary(doc.collection)
      assert is_map(doc.data)
      assert is_binary(doc.created_at)
      assert is_binary(doc.updated_at)
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

defmodule SquirrelDB.ProtocolTest do
  use ExUnit.Case, async: true

  describe "Message Protocol" do
    test "ping message" do
      msg = %{"type" => "Ping"}
      assert msg["type"] == "Ping"
    end

    test "query message" do
      msg = %{
        "type" => "Query",
        "id" => "req-123",
        "query" => ~s|db.table("users").run()|
      }
      assert msg["type"] == "Query"
      assert msg["id"] == "req-123"
      assert String.contains?(msg["query"], "users")
    end

    test "insert message" do
      msg = %{
        "type" => "Insert",
        "id" => "req-456",
        "collection" => "users",
        "data" => %{"name" => "Alice"}
      }
      assert msg["type"] == "Insert"
      assert msg["collection"] == "users"
      assert msg["data"] == %{"name" => "Alice"}
    end

    test "update message" do
      msg = %{
        "type" => "Update",
        "id" => "req-789",
        "collection" => "users",
        "document_id" => "doc-123",
        "data" => %{"name" => "Bob"}
      }
      assert msg["type"] == "Update"
      assert msg["document_id"] == "doc-123"
    end

    test "delete message" do
      msg = %{
        "type" => "Delete",
        "id" => "req-101",
        "collection" => "users",
        "document_id" => "doc-123"
      }
      assert msg["type"] == "Delete"
      assert msg["document_id"] == "doc-123"
    end

    test "subscribe message" do
      msg = %{
        "type" => "Subscribe",
        "id" => "req-202",
        "query" => ~s|db.table("users").changes()|
      }
      assert msg["type"] == "Subscribe"
      assert String.contains?(msg["query"], "changes")
    end

    test "unsubscribe message" do
      msg = %{
        "type" => "Unsubscribe",
        "id" => "req-303",
        "subscription_id" => "sub-123"
      }
      assert msg["type"] == "Unsubscribe"
      assert msg["subscription_id"] == "sub-123"
    end
  end

  describe "Server Response Protocol" do
    test "pong response" do
      response = %{"type" => "Pong"}
      assert response["type"] == "Pong"
    end

    test "result response" do
      response = %{
        "type" => "Result",
        "id" => "req-123",
        "documents" => [
          %{"id" => "1", "collection" => "users", "data" => %{"name" => "Alice"}, "created_at" => "", "updated_at" => ""}
        ]
      }
      assert response["type"] == "Result"
      assert length(response["documents"]) == 1
    end

    test "error response" do
      response = %{
        "type" => "Error",
        "id" => "req-123",
        "message" => "Query failed"
      }
      assert response["type"] == "Error"
      assert response["message"] == "Query failed"
    end

    test "subscribed response" do
      response = %{
        "type" => "Subscribed",
        "id" => "req-123",
        "subscription_id" => "sub-456"
      }
      assert response["type"] == "Subscribed"
      assert response["subscription_id"] == "sub-456"
    end

    test "change response" do
      response = %{
        "type" => "Change",
        "subscription_id" => "sub-456",
        "change" => %{
          "type" => "insert",
          "new" => %{"id" => "1", "collection" => "users", "data" => %{}, "created_at" => "", "updated_at" => ""}
        }
      }
      assert response["type"] == "Change"
      assert response["change"]["type"] == "insert"
    end
  end
end
