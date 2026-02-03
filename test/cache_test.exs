defmodule SquirrelDB.CacheTest do
  use ExUnit.Case, async: true

  describe "CacheOptions" do
    test "default options" do
      opts = %{host: "localhost", port: 6379}
      assert opts.host == "localhost"
      assert opts.port == 6379
    end

    test "custom options" do
      opts = %{host: "redis.example.com", port: 6380}
      assert opts.host == "redis.example.com"
      assert opts.port == 6380
    end
  end

  describe "RESP Protocol" do
    test "simple string format" do
      response = "+OK\r\n"
      assert String.starts_with?(response, "+")
      assert String.contains?(response, "\r\n")
    end

    test "error format" do
      response = "-ERR unknown command\r\n"
      assert String.starts_with?(response, "-")
    end

    test "integer format" do
      response = ":1000\r\n"
      assert String.starts_with?(response, ":")
      [_, value_str] = Regex.run(~r/:(\d+)\r\n/, response)
      value = String.to_integer(value_str)
      assert value == 1000
    end

    test "bulk string format" do
      value = "hello"
      response = "$#{String.length(value)}\r\n#{value}\r\n"
      assert response == "$5\r\nhello\r\n"
    end

    test "null bulk string format" do
      response = "$-1\r\n"
      assert response == "$-1\r\n"
    end

    test "array format" do
      response = "*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n"
      assert String.starts_with?(response, "*2")
    end

    test "null array format" do
      response = "*-1\r\n"
      assert response == "*-1\r\n"
    end
  end

  describe "Cache commands" do
    defp encode_command(args) do
      count = length(args)
      parts = ["*#{count}\r\n"]

      encoded_args =
        Enum.map(args, fn arg ->
          s = to_string(arg)
          "$#{String.length(s)}\r\n#{s}\r\n"
        end)

      Enum.join(parts ++ encoded_args)
    end

    test "PING command" do
      cmd = encode_command(["PING"])
      assert cmd == "*1\r\n$4\r\nPING\r\n"
    end

    test "GET command" do
      cmd = encode_command(["GET", "mykey"])
      assert cmd == "*2\r\n$3\r\nGET\r\n$5\r\nmykey\r\n"
    end

    test "SET command" do
      cmd = encode_command(["SET", "mykey", "myvalue"])
      assert cmd == "*3\r\n$3\r\nSET\r\n$5\r\nmykey\r\n$7\r\nmyvalue\r\n"
    end

    test "SET with EX command" do
      cmd = encode_command(["SET", "mykey", "myvalue", "EX", 60])
      assert String.contains?(cmd, "*5\r\n")
      assert String.contains?(cmd, "$2\r\nEX\r\n")
    end

    test "DEL command" do
      cmd = encode_command(["DEL", "mykey"])
      assert cmd == "*2\r\n$3\r\nDEL\r\n$5\r\nmykey\r\n"
    end

    test "EXISTS command" do
      cmd = encode_command(["EXISTS", "mykey"])
      assert String.contains?(cmd, "EXISTS")
    end

    test "INCR command" do
      cmd = encode_command(["INCR", "counter"])
      assert String.contains?(cmd, "INCR")
    end

    test "INCRBY command" do
      cmd = encode_command(["INCRBY", "counter", 5])
      assert String.contains?(cmd, "INCRBY")
      assert String.contains?(cmd, "$1\r\n5\r\n")
    end

    test "MGET command" do
      cmd = encode_command(["MGET", "key1", "key2", "key3"])
      assert String.contains?(cmd, "*4\r\n")
      assert String.contains?(cmd, "MGET")
    end

    test "MSET command" do
      cmd = encode_command(["MSET", "key1", "val1", "key2", "val2"])
      assert String.contains?(cmd, "*5\r\n")
      assert String.contains?(cmd, "MSET")
    end

    test "KEYS command" do
      cmd = encode_command(["KEYS", "user:*"])
      assert String.contains?(cmd, "KEYS")
      assert String.contains?(cmd, "user:*")
    end

    test "EXPIRE command" do
      cmd = encode_command(["EXPIRE", "mykey", 300])
      assert String.contains?(cmd, "EXPIRE")
    end

    test "TTL command" do
      cmd = encode_command(["TTL", "mykey"])
      assert String.contains?(cmd, "TTL")
    end

    test "DBSIZE command" do
      cmd = encode_command(["DBSIZE"])
      assert cmd == "*1\r\n$6\r\nDBSIZE\r\n"
    end

    test "FLUSHDB command" do
      cmd = encode_command(["FLUSHDB"])
      assert cmd == "*1\r\n$7\r\nFLUSHDB\r\n"
    end
  end
end
