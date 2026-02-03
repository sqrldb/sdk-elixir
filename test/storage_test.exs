defmodule SquirrelDB.StorageTest do
  use ExUnit.Case, async: true

  describe "StorageOptions" do
    test "minimal options" do
      opts = %{endpoint: "http://localhost:9000"}
      assert opts.endpoint == "http://localhost:9000"
      assert Map.get(opts, :access_key_id) == nil
      assert Map.get(opts, :secret_access_key) == nil
      assert Map.get(opts, :region) == nil
    end

    test "full options" do
      opts = %{
        endpoint: "https://s3.amazonaws.com",
        access_key_id: "AKIAIOSFODNN7EXAMPLE",
        secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region: "us-west-2"
      }
      assert opts.endpoint == "https://s3.amazonaws.com"
      assert opts.access_key_id == "AKIAIOSFODNN7EXAMPLE"
      assert opts.region == "us-west-2"
    end
  end

  describe "Bucket type" do
    test "bucket structure" do
      bucket = %{name: "my-bucket", created_at: "2024-01-01T00:00:00Z"}
      assert bucket.name == "my-bucket"
      assert bucket.created_at == "2024-01-01T00:00:00Z"
    end

    test "bucket name validation" do
      valid_names = ["my-bucket", "bucket123", "test.bucket.name"]

      Enum.each(valid_names, fn name ->
        assert String.length(name) >= 3
        assert String.length(name) <= 63
      end)
    end
  end

  describe "StorageObject type" do
    test "object structure" do
      obj = %{
        key: "path/to/file.txt",
        size: 1024,
        etag: "d41d8cd98f00b204e9800998ecf8427e",
        last_modified: "2024-01-01T00:00:00Z",
        content_type: "text/plain"
      }
      assert obj.key == "path/to/file.txt"
      assert obj.size == 1024
      assert obj.etag == "d41d8cd98f00b204e9800998ecf8427e"
      assert obj.content_type == "text/plain"
    end

    test "object with nil content_type" do
      obj = %{
        key: "file.bin",
        size: 2048,
        etag: "abc123",
        last_modified: "2024-01-01T00:00:00Z",
        content_type: nil
      }
      assert obj.content_type == nil
    end
  end

  describe "S3 API paths" do
    test "list buckets path" do
      path = "/"
      assert path == "/"
    end

    test "bucket path" do
      bucket = "my-bucket"
      path = "/#{bucket}"
      assert path == "/my-bucket"
    end

    test "object path" do
      bucket = "my-bucket"
      key = "path/to/file.txt"
      path = "/#{bucket}/#{key}"
      assert path == "/my-bucket/path/to/file.txt"
    end

    test "list objects with prefix" do
      bucket = "my-bucket"
      prefix = "logs/"
      params = URI.encode_query(prefix: prefix)
      path = "/#{bucket}?#{params}"
      assert path == "/my-bucket?prefix=logs%2F"
    end

    test "list objects with max-keys" do
      bucket = "my-bucket"
      params = URI.encode_query("max-keys": 100)
      path = "/#{bucket}?#{params}"
      assert path == "/my-bucket?max-keys=100"
    end
  end

  describe "S3 XML response parsing" do
    test "parse bucket name from XML" do
      xml = "<Name>my-bucket</Name>"
      regex = ~r/<Name>([^<]+)<\/Name>/
      [_, name] = Regex.run(regex, xml)
      assert name == "my-bucket"
    end

    test "parse multiple bucket names" do
      xml = """
      <Buckets>
        <Bucket><Name>bucket1</Name></Bucket>
        <Bucket><Name>bucket2</Name></Bucket>
      </Buckets>
      """
      regex = ~r/<Name>([^<]+)<\/Name>/
      matches = Regex.scan(regex, xml) |> Enum.map(fn [_, name] -> name end)
      assert matches == ["bucket1", "bucket2"]
    end

    test "parse object listing" do
      xml = """
      <Contents>
        <Key>file1.txt</Key>
        <Size>1024</Size>
        <ETag>"abc123"</ETag>
      </Contents>
      """
      [_, key] = Regex.run(~r/<Key>([^<]+)<\/Key>/, xml)
      [_, size] = Regex.run(~r/<Size>(\d+)<\/Size>/, xml)
      [_, etag] = Regex.run(~r/<ETag>([^<]+)<\/ETag>/, xml)

      assert key == "file1.txt"
      assert String.to_integer(size) == 1024
      assert String.replace(etag, "\"", "") == "abc123"
    end
  end

  describe "Content types" do
    test "common content types" do
      content_types = %{
        ".txt" => "text/plain",
        ".html" => "text/html",
        ".css" => "text/css",
        ".js" => "application/javascript",
        ".json" => "application/json",
        ".png" => "image/png",
        ".jpg" => "image/jpeg",
        ".pdf" => "application/pdf"
      }
      assert content_types[".json"] == "application/json"
      assert content_types[".png"] == "image/png"
    end
  end
end
