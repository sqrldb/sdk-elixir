defmodule SquirrelDB.Cache do
  @moduledoc """
  Redis-compatible cache client for SquirrelDB.
  Uses RESP protocol over TCP.

  ## Example

      {:ok, conn} = SquirrelDB.Cache.connect("localhost", 6379)
      :ok = SquirrelDB.Cache.set(conn, "mykey", "myvalue")
      {:ok, "myvalue"} = SquirrelDB.Cache.get(conn, "mykey")
      :ok = SquirrelDB.Cache.close(conn)

  ## With TTL

      :ok = SquirrelDB.Cache.set(conn, "temp", "value", ttl: 60)
  """

  use GenServer

  @default_host "localhost"
  @default_port 6379
  @timeout 5000

  # Client API

  @doc """
  Start a cache connection as a linked process.
  Options:
    - host: Host to connect to (default: "localhost")
    - port: Port to connect to (default: 6379)
    - timeout: Connection timeout in ms (default: 5000)
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    host = Keyword.get(opts, :host, @default_host)
    port = Keyword.get(opts, :port, @default_port)
    timeout = Keyword.get(opts, :timeout, @timeout)
    GenServer.start_link(__MODULE__, {host, port, timeout})
  end

  @doc "Connect to a Redis-compatible cache server"
  @spec connect(String.t(), integer()) :: {:ok, pid()} | {:error, term()}
  def connect(host \\ @default_host, port \\ @default_port) do
    start_link(host: host, port: port)
  end

  @doc "Get a value by key"
  @spec get(pid(), String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def get(conn, key) do
    GenServer.call(conn, {:command, ["GET", key]})
  end

  @doc """
  Set a key-value pair.
  Options:
    - ttl: Time to live in seconds
  """
  @spec set(pid(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def set(conn, key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl)

    command =
      if ttl do
        ["SET", key, value, "EX", to_string(ttl)]
      else
        ["SET", key, value]
      end

    case GenServer.call(conn, {:command, command}) do
      {:ok, "OK"} -> :ok
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc "Delete a key"
  @spec del(pid(), String.t()) :: {:ok, integer()} | {:error, term()}
  def del(conn, key) do
    GenServer.call(conn, {:command, ["DEL", key]})
  end

  @doc "Check if a key exists"
  @spec exists(pid(), String.t()) :: {:ok, boolean()} | {:error, term()}
  def exists(conn, key) do
    case GenServer.call(conn, {:command, ["EXISTS", key]}) do
      {:ok, 1} -> {:ok, true}
      {:ok, 0} -> {:ok, false}
      error -> error
    end
  end

  @doc "Set expiration on a key"
  @spec expire(pid(), String.t(), integer()) :: {:ok, boolean()} | {:error, term()}
  def expire(conn, key, seconds) do
    case GenServer.call(conn, {:command, ["EXPIRE", key, to_string(seconds)]}) do
      {:ok, 1} -> {:ok, true}
      {:ok, 0} -> {:ok, false}
      error -> error
    end
  end

  @doc "Get TTL of a key"
  @spec ttl(pid(), String.t()) :: {:ok, integer()} | {:error, term()}
  def ttl(conn, key) do
    GenServer.call(conn, {:command, ["TTL", key]})
  end

  @doc "Remove expiration from a key"
  @spec persist(pid(), String.t()) :: {:ok, boolean()} | {:error, term()}
  def persist(conn, key) do
    case GenServer.call(conn, {:command, ["PERSIST", key]}) do
      {:ok, 1} -> {:ok, true}
      {:ok, 0} -> {:ok, false}
      error -> error
    end
  end

  @doc "Increment a key by 1"
  @spec incr(pid(), String.t()) :: {:ok, integer()} | {:error, term()}
  def incr(conn, key) do
    GenServer.call(conn, {:command, ["INCR", key]})
  end

  @doc "Decrement a key by 1"
  @spec decr(pid(), String.t()) :: {:ok, integer()} | {:error, term()}
  def decr(conn, key) do
    GenServer.call(conn, {:command, ["DECR", key]})
  end

  @doc "Increment a key by amount"
  @spec incrby(pid(), String.t(), integer()) :: {:ok, integer()} | {:error, term()}
  def incrby(conn, key, amount) do
    GenServer.call(conn, {:command, ["INCRBY", key, to_string(amount)]})
  end

  @doc "Get all keys matching pattern"
  @spec keys(pid(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def keys(conn, pattern \\ "*") do
    GenServer.call(conn, {:command, ["KEYS", pattern]})
  end

  @doc "Get multiple values"
  @spec mget(pid(), [String.t()]) :: {:ok, [String.t() | nil]} | {:error, term()}
  def mget(conn, keys) when is_list(keys) do
    GenServer.call(conn, {:command, ["MGET" | keys]})
  end

  @doc "Set multiple key-value pairs"
  @spec mset(pid(), [{String.t(), String.t()}] | map()) :: :ok | {:error, term()}
  def mset(conn, pairs) when is_list(pairs) do
    args = Enum.flat_map(pairs, fn {k, v} -> [k, v] end)

    case GenServer.call(conn, {:command, ["MSET" | args]}) do
      {:ok, "OK"} -> :ok
      error -> error
    end
  end

  def mset(conn, pairs) when is_map(pairs) do
    mset(conn, Map.to_list(pairs))
  end

  @doc "Get number of keys in database"
  @spec dbsize(pid()) :: {:ok, integer()} | {:error, term()}
  def dbsize(conn) do
    GenServer.call(conn, {:command, ["DBSIZE"]})
  end

  @doc "Flush current database"
  @spec flush(pid()) :: :ok | {:error, term()}
  def flush(conn) do
    case GenServer.call(conn, {:command, ["FLUSHDB"]}) do
      {:ok, "OK"} -> :ok
      error -> error
    end
  end

  @doc "Get server info"
  @spec info(pid()) :: {:ok, String.t()} | {:error, term()}
  def info(conn) do
    GenServer.call(conn, {:command, ["INFO"]})
  end

  @doc "Ping the server"
  @spec ping(pid()) :: :ok | {:error, term()}
  def ping(conn) do
    case GenServer.call(conn, {:command, ["PING"]}) do
      {:ok, "PONG"} -> :ok
      error -> error
    end
  end

  @doc "Close the connection"
  @spec close(pid()) :: :ok
  def close(conn) do
    GenServer.stop(conn, :normal)
  end

  # GenServer callbacks

  @impl true
  def init({host, port, timeout}) do
    host_charlist = to_charlist(host)

    case :gen_tcp.connect(host_charlist, port, [:binary, active: false, packet: :raw], timeout) do
      {:ok, socket} ->
        {:ok, %{socket: socket}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:command, args}, _from, %{socket: socket} = state) do
    command = encode_command(args)

    case :gen_tcp.send(socket, command) do
      :ok ->
        case read_response(socket) do
          {:ok, response} ->
            {:reply, {:ok, response}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def terminate(_reason, %{socket: socket}) do
    :gen_tcp.close(socket)
  end

  # RESP Protocol encoding/decoding

  defp encode_command(args) do
    parts = ["*#{length(args)}\r\n"]

    encoded =
      Enum.reduce(args, parts, fn arg, acc ->
        str = to_string(arg)
        acc ++ ["$#{byte_size(str)}\r\n", str, "\r\n"]
      end)

    IO.iodata_to_binary(encoded)
  end

  defp read_response(socket) do
    case :gen_tcp.recv(socket, 1, @timeout) do
      {:ok, <<type>>} ->
        parse_response(socket, type)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_response(socket, ?+) do
    read_line(socket)
  end

  defp parse_response(socket, ?-) do
    case read_line(socket) do
      {:ok, error_msg} -> {:error, error_msg}
      error -> error
    end
  end

  defp parse_response(socket, ?:) do
    case read_line(socket) do
      {:ok, line} -> {:ok, String.to_integer(line)}
      error -> error
    end
  end

  defp parse_response(socket, ?$) do
    case read_line(socket) do
      {:ok, "-1"} ->
        {:ok, nil}

      {:ok, length_str} ->
        length = String.to_integer(length_str)
        read_bulk_string(socket, length)

      error ->
        error
    end
  end

  defp parse_response(socket, ?*) do
    case read_line(socket) do
      {:ok, "-1"} ->
        {:ok, nil}

      {:ok, count_str} ->
        count = String.to_integer(count_str)
        read_array(socket, count, [])

      error ->
        error
    end
  end

  defp read_line(socket) do
    read_line(socket, <<>>)
  end

  defp read_line(socket, acc) do
    case :gen_tcp.recv(socket, 1, @timeout) do
      {:ok, <<?\r>>} ->
        case :gen_tcp.recv(socket, 1, @timeout) do
          {:ok, <<?\n>>} -> {:ok, acc}
          {:error, reason} -> {:error, reason}
        end

      {:ok, <<byte>>} ->
        read_line(socket, acc <> <<byte>>)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_bulk_string(socket, length) do
    case :gen_tcp.recv(socket, length + 2, @timeout) do
      {:ok, data} ->
        <<bulk::binary-size(length), "\r\n">> = data
        {:ok, bulk}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_array(_socket, 0, acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp read_array(socket, count, acc) do
    case read_response(socket) do
      {:ok, element} ->
        read_array(socket, count - 1, [element | acc])

      error ->
        error
    end
  end
end
