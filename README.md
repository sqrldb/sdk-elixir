# SquirrelDB Elixir SDK

Official Elixir client for SquirrelDB.

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:squirreldb, "~> 0.1"}
  ]
end
```

## Quick Start

```elixir
# Connect to database
{:ok, db} = SquirrelDB.connect(
  host: "localhost",
  port: 8080,
  token: System.get_env("SQUIRRELDB_TOKEN")
)

# Insert a document
{:ok, user} = SquirrelDB.insert(db, "users", %{
  name: "Alice",
  email: "alice@example.com"
})
IO.puts("Created user: #{user["id"]}")

# Query documents
{:ok, users} = db
  |> SquirrelDB.table("users")
  |> SquirrelDB.filter("u => u.status === 'active'")
  |> SquirrelDB.run()

# Subscribe to changes
SquirrelDB.subscribe(db, "messages", fn change ->
  IO.inspect(change, label: "Change")
end)
```

## Documentation

Visit [squirreldb.com/docs/sdks](https://squirreldb.com/docs/sdks) for full documentation.

## License

Apache License 2.0 - see [LICENSE](LICENSE) for details.
