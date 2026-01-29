defmodule SquirrelDB do
  @moduledoc """
  Elixir client for SquirrelDB.

  ## Modules

  - `SquirrelDB` - WebSocket client for realtime database operations
  - `SquirrelDB.Query` - Query builder with MongoDB-like syntax
  - `SquirrelDB.Storage` - S3-compatible object storage client
  - `SquirrelDB.Cache` - Redis-compatible cache client (RESP protocol)

  ## Example

      {:ok, client} = SquirrelDB.connect("localhost:8080")
      {:ok, docs} = SquirrelDB.query(client, ~s|db.table("users").run()|)
      {:ok, doc} = SquirrelDB.insert(client, "users", %{name: "Alice", age: 30})
      :ok = SquirrelDB.close(client)

  ## Cache Example

      {:ok, cache} = SquirrelDB.Cache.connect("localhost", 6379)
      :ok = SquirrelDB.Cache.set(cache, "key", "value", ttl: 60)
      {:ok, "value"} = SquirrelDB.Cache.get(cache, "key")
  """

  use GenServer
  require Logger

  defmodule Document do
    @moduledoc "A document stored in SquirrelDB"
    defstruct [:id, :collection, :data, :created_at, :updated_at]

    def from_map(map) do
      %__MODULE__{
        id: map["id"],
        collection: map["collection"],
        data: map["data"],
        created_at: map["created_at"],
        updated_at: map["updated_at"]
      }
    end
  end

  defmodule ChangeEvent do
    @moduledoc "A change event from a subscription"
    defstruct [:type, :document, :new, :old]

    def from_map(%{"type" => "initial", "document" => doc}) do
      %__MODULE__{type: :initial, document: Document.from_map(doc)}
    end

    def from_map(%{"type" => "insert", "new" => doc}) do
      %__MODULE__{type: :insert, new: Document.from_map(doc)}
    end

    def from_map(%{"type" => "update", "old" => old, "new" => new}) do
      %__MODULE__{type: :update, old: old, new: Document.from_map(new)}
    end

    def from_map(%{"type" => "delete", "old" => old}) do
      %__MODULE__{type: :delete, old: Document.from_map(old)}
    end
  end

  # Client API

  @doc "Connect to a SquirrelDB server"
  def connect(url, opts \\ []) do
    GenServer.start_link(__MODULE__, {url, opts})
  end

  @doc "Execute a query"
  def query(client, q) do
    GenServer.call(client, {:query, q}, :infinity)
  end

  @doc """
  Subscribe to changes on a table (fluent API).

  ## Examples

      SquirrelDB.subscribe(client, "users")
      |> SquirrelDB.changes(fn change -> ... end)

      SquirrelDB.subscribe(client, "users")
      |> SquirrelDB.find(age: {:gt, 21})
      |> SquirrelDB.changes(fn change -> ... end)
  """
  def subscribe(client, table_name) when is_binary(table_name) do
    %{client: client, table: table_name, filter: nil}
  end

  @doc "Add a filter to the subscription"
  def find(%{client: _, table: _, filter: _} = builder, conditions) do
    %{builder | filter: conditions}
  end

  @doc "Subscribe to changes"
  def changes(%{client: client, table: table, filter: filter}, callback) when is_function(callback, 1) do
    query = %{"table" => table, "changes" => %{"includeInitial" => false}}
    query =
      if filter do
        filter_structured = SquirrelDB.Query.table(table) |> SquirrelDB.Query.find(filter) |> SquirrelDB.Query.compile_structured() |> Map.get("filter")
        if filter_structured, do: Map.put(query, "filter", filter_structured), else: query
      else
        query
      end
    GenServer.call(client, {:subscribe, query, callback}, :infinity)
  end

  @doc "Subscribe to changes with raw query string (legacy)"
  def subscribe_raw(client, q, callback) when is_function(callback, 1) do
    GenServer.call(client, {:subscribe, q, callback}, :infinity)
  end

  @doc "Unsubscribe from changes"
  def unsubscribe(client, subscription_id) do
    GenServer.call(client, {:unsubscribe, subscription_id}, :infinity)
  end

  @doc "Insert a document"
  def insert(client, collection, data) do
    GenServer.call(client, {:insert, collection, data}, :infinity)
  end

  @doc "Update a document"
  def update(client, collection, document_id, data) do
    GenServer.call(client, {:update, collection, document_id, data}, :infinity)
  end

  @doc "Delete a document"
  def delete(client, collection, document_id) do
    GenServer.call(client, {:delete, collection, document_id}, :infinity)
  end

  @doc "List all collections"
  def list_collections(client) do
    GenServer.call(client, :list_collections, :infinity)
  end

  @doc "Ping the server"
  def ping(client) do
    GenServer.call(client, :ping, :infinity)
  end

  @doc "Close the connection"
  def close(client) do
    GenServer.stop(client, :normal)
  end

  # GenServer callbacks

  @impl true
  def init({url, _opts}) do
    url = normalize_url(url)

    case WebSockex.start_link(url, SquirrelDB.WebSocket, %{parent: self()}) do
      {:ok, ws} ->
        {:ok,
         %{
           ws: ws,
           pending: %{},
           subscriptions: %{}
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:query, q}, from, state) do
    id = generate_id()
    msg = %{type: "query", id: id, query: q}
    send_and_track(state, id, msg, from, :query)
  end

  @impl true
  def handle_call({:subscribe, q, callback}, from, state) do
    id = generate_id()
    msg = %{type: "subscribe", id: id, query: q}
    state = put_in(state.subscriptions[id], callback)
    send_and_track(state, id, msg, from, :subscribe)
  end

  @impl true
  def handle_call({:unsubscribe, subscription_id}, from, state) do
    msg = %{type: "unsubscribe", id: subscription_id}
    state = update_in(state.subscriptions, &Map.delete(&1, subscription_id))
    send_and_track(state, subscription_id, msg, from, :unsubscribe)
  end

  @impl true
  def handle_call({:insert, collection, data}, from, state) do
    id = generate_id()
    msg = %{type: "insert", id: id, collection: collection, data: data}
    send_and_track(state, id, msg, from, :insert)
  end

  @impl true
  def handle_call({:update, collection, document_id, data}, from, state) do
    id = generate_id()
    msg = %{type: "update", id: id, collection: collection, document_id: document_id, data: data}
    send_and_track(state, id, msg, from, :update)
  end

  @impl true
  def handle_call({:delete, collection, document_id}, from, state) do
    id = generate_id()
    msg = %{type: "delete", id: id, collection: collection, document_id: document_id}
    send_and_track(state, id, msg, from, :delete)
  end

  @impl true
  def handle_call(:list_collections, from, state) do
    id = generate_id()
    msg = %{type: "listcollections", id: id}
    send_and_track(state, id, msg, from, :list_collections)
  end

  @impl true
  def handle_call(:ping, from, state) do
    id = generate_id()
    msg = %{type: "ping", id: id}
    send_and_track(state, id, msg, from, :ping)
  end

  @impl true
  def handle_info({:ws_message, data}, state) do
    case Jason.decode(data) do
      {:ok, %{"type" => "change", "id" => id, "change" => change}} ->
        if callback = state.subscriptions[id] do
          callback.(ChangeEvent.from_map(change))
        end

        {:noreply, state}

      {:ok, %{"type" => type, "id" => id} = msg} ->
        case Map.pop(state.pending, id) do
          {{from, op}, pending} ->
            reply = format_reply(type, msg, op)
            GenServer.reply(from, reply)
            {:noreply, %{state | pending: pending}}

          {nil, _} ->
            {:noreply, state}
        end

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private functions

  defp normalize_url(url) do
    if String.starts_with?(url, "ws://") or String.starts_with?(url, "wss://") do
      url
    else
      "ws://#{url}"
    end
  end

  defp generate_id, do: UUID.uuid4()

  defp send_and_track(state, id, msg, from, op) do
    WebSockex.send_frame(state.ws, {:text, Jason.encode!(msg)})
    state = put_in(state.pending[id], {from, op})
    {:noreply, state}
  end

  defp format_reply("error", %{"error" => error}, _op), do: {:error, error}
  defp format_reply("pong", _, :ping), do: :ok
  defp format_reply("subscribed", _, :subscribe), do: {:ok, :subscribed}
  defp format_reply("unsubscribed", _, :unsubscribe), do: :ok

  defp format_reply("result", %{"data" => data}, op) when op in [:query, :list_collections] do
    if op == :query do
      {:ok, Enum.map(data, &Document.from_map/1)}
    else
      {:ok, data}
    end
  end

  defp format_reply("result", %{"data" => data}, _op) do
    {:ok, Document.from_map(data)}
  end
end

defmodule SquirrelDB.WebSocket do
  @moduledoc false
  use WebSockex

  def handle_frame({:text, data}, %{parent: parent} = state) do
    send(parent, {:ws_message, data})
    {:ok, state}
  end

  def handle_frame(_, state), do: {:ok, state}
end
