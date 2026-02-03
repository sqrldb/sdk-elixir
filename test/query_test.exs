defmodule SquirrelDB.QueryTest do
  use ExUnit.Case, async: true

  describe "FieldExpr" do
    test "eq creates equal condition" do
      cond = %{field: "age", operator: "$eq", value: 25}
      assert cond.field == "age"
      assert cond.operator == "$eq"
      assert cond.value == 25
    end

    test "ne creates not equal condition" do
      cond = %{field: "status", operator: "$ne", value: "inactive"}
      assert cond.operator == "$ne"
      assert cond.value == "inactive"
    end

    test "gt creates greater than condition" do
      cond = %{field: "price", operator: "$gt", value: 100}
      assert cond.operator == "$gt"
    end

    test "gte creates greater than or equal condition" do
      cond = %{field: "count", operator: "$gte", value: 10}
      assert cond.operator == "$gte"
    end

    test "lt creates less than condition" do
      cond = %{field: "age", operator: "$lt", value: 18}
      assert cond.operator == "$lt"
    end

    test "lte creates less than or equal condition" do
      cond = %{field: "rating", operator: "$lte", value: 5}
      assert cond.operator == "$lte"
    end

    test "in creates array inclusion condition" do
      cond = %{field: "role", operator: "$in", value: ["admin", "mod"]}
      assert cond.operator == "$in"
      assert cond.value == ["admin", "mod"]
    end

    test "not_in creates array exclusion condition" do
      cond = %{field: "status", operator: "$nin", value: ["banned", "deleted"]}
      assert cond.operator == "$nin"
    end

    test "contains creates substring condition" do
      cond = %{field: "name", operator: "$contains", value: "test"}
      assert cond.operator == "$contains"
    end

    test "starts_with creates prefix condition" do
      cond = %{field: "email", operator: "$startsWith", value: "admin"}
      assert cond.operator == "$startsWith"
    end

    test "ends_with creates suffix condition" do
      cond = %{field: "email", operator: "$endsWith", value: ".com"}
      assert cond.operator == "$endsWith"
    end

    test "exists creates existence condition" do
      cond = %{field: "avatar", operator: "$exists", value: true}
      assert cond.operator == "$exists"
      assert cond.value == true
    end

    test "exists false creates non-existence condition" do
      cond = %{field: "deleted_at", operator: "$exists", value: false}
      assert cond.value == false
    end
  end

  describe "StructuredQuery" do
    test "minimal query" do
      query = %{table: "users"}
      assert query.table == "users"
      assert Map.get(query, :filter) == nil
    end

    test "query with filter" do
      query = %{
        table: "users",
        filter: %{"age" => %{"$gt" => 21}}
      }
      assert query.filter["age"]["$gt"] == 21
    end

    test "query with sort" do
      query = %{
        table: "users",
        sort: [%{field: "name", direction: "asc"}]
      }
      assert length(query.sort) == 1
      assert hd(query.sort).field == "name"
      assert hd(query.sort).direction == "asc"
    end

    test "query with multiple sorts" do
      query = %{
        table: "posts",
        sort: [
          %{field: "pinned", direction: "desc"},
          %{field: "created_at", direction: "desc"}
        ]
      }
      assert length(query.sort) == 2
    end

    test "query with limit" do
      query = %{table: "users", limit: 10}
      assert query.limit == 10
    end

    test "query with skip" do
      query = %{table: "users", skip: 20}
      assert query.skip == 20
    end

    test "query with changes" do
      query = %{
        table: "messages",
        changes: %{include_initial: true}
      }
      assert query.changes.include_initial == true
    end

    test "full query" do
      query = %{
        table: "users",
        filter: %{
          "age" => %{"$gte" => 18},
          "status" => %{"$eq" => "active"}
        },
        sort: [%{field: "name", direction: "asc"}],
        limit: 50,
        skip: 100
      }
      assert query.table == "users"
      assert query.filter["age"]["$gte"] == 18
      assert query.filter["status"]["$eq"] == "active"
      assert query.limit == 50
      assert query.skip == 100
    end

    test "compile to JSON" do
      query = %{table: "users", limit: 10}
      json = Jason.encode!(query)
      parsed = Jason.decode!(json)
      assert parsed["table"] == "users"
      assert parsed["limit"] == 10
    end
  end

  describe "Logical operators" do
    test "and combines conditions" do
      cond = %{
        field: "$and",
        operator: "$and",
        value: [
          %{field: "age", operator: "$gte", value: 18},
          %{field: "active", operator: "$eq", value: true}
        ]
      }
      assert cond.field == "$and"
      assert cond.operator == "$and"
      assert length(cond.value) == 2
    end

    test "or combines conditions" do
      cond = %{
        field: "$or",
        operator: "$or",
        value: [
          %{field: "role", operator: "$eq", value: "admin"},
          %{field: "role", operator: "$eq", value: "moderator"}
        ]
      }
      assert cond.field == "$or"
    end

    test "not negates condition" do
      cond = %{
        field: "$not",
        operator: "$not",
        value: %{field: "banned", operator: "$eq", value: true}
      }
      assert cond.field == "$not"
    end
  end
end
