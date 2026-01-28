defmodule SquirrelDB.Storage do
  @moduledoc """
  Object storage client for SquirrelDB.
  S3-compatible API.

  ## Example

      storage = SquirrelDB.Storage.new("http://localhost:9000",
        access_key: "...",
        secret_key: "..."
      )

      {:ok, _} = SquirrelDB.Storage.create_bucket(storage, "my-bucket")
      {:ok, etag} = SquirrelDB.Storage.put_object(storage, "my-bucket", "hello.txt", "Hello!")
      {:ok, data} = SquirrelDB.Storage.get_object(storage, "my-bucket", "hello.txt")
  """

  defstruct endpoint: nil,
            access_key: nil,
            secret_key: nil,
            region: "us-east-1"

  @type t :: %__MODULE__{
          endpoint: String.t(),
          access_key: String.t() | nil,
          secret_key: String.t() | nil,
          region: String.t()
        }

  defmodule Bucket do
    @moduledoc "Storage bucket"
    defstruct [:name, :created_at]
    @type t :: %__MODULE__{name: String.t(), created_at: DateTime.t()}
  end

  defmodule Object do
    @moduledoc "Storage object"
    defstruct [:key, :size, :etag, :last_modified, :content_type]

    @type t :: %__MODULE__{
            key: String.t(),
            size: non_neg_integer(),
            etag: String.t(),
            last_modified: DateTime.t(),
            content_type: String.t() | nil
          }
  end

  defmodule MultipartUpload do
    @moduledoc "Multipart upload info"
    defstruct [:upload_id, :bucket, :key]
    @type t :: %__MODULE__{upload_id: String.t(), bucket: String.t(), key: String.t()}
  end

  defmodule UploadPart do
    @moduledoc "Uploaded part"
    defstruct [:part_number, :etag]
    @type t :: %__MODULE__{part_number: non_neg_integer(), etag: String.t()}
  end

  @doc "Create a new storage client"
  @spec new(String.t(), keyword()) :: t()
  def new(endpoint, opts \\ []) do
    %__MODULE__{
      endpoint: String.trim_trailing(endpoint, "/"),
      access_key: Keyword.get(opts, :access_key),
      secret_key: Keyword.get(opts, :secret_key),
      region: Keyword.get(opts, :region, "us-east-1")
    }
  end

  @doc "List all buckets"
  @spec list_buckets(t()) :: {:ok, [Bucket.t()]} | {:error, term()}
  def list_buckets(storage) do
    case request(storage, :get, "/") do
      {:ok, body} ->
        buckets = parse_buckets_xml(body)
        {:ok, buckets}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Create a bucket"
  @spec create_bucket(t(), String.t()) :: :ok | {:error, term()}
  def create_bucket(storage, name) do
    case request(storage, :put, "/#{name}") do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Delete a bucket"
  @spec delete_bucket(t(), String.t()) :: :ok | {:error, term()}
  def delete_bucket(storage, name) do
    case request(storage, :delete, "/#{name}") do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Check if bucket exists"
  @spec bucket_exists?(t(), String.t()) :: boolean()
  def bucket_exists?(storage, name) do
    case request(storage, :head, "/#{name}") do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc "List objects in a bucket"
  @spec list_objects(t(), String.t(), keyword()) :: {:ok, [Object.t()]} | {:error, term()}
  def list_objects(storage, bucket, opts \\ []) do
    params =
      []
      |> maybe_add_param(:prefix, Keyword.get(opts, :prefix))
      |> maybe_add_param(:"max-keys", Keyword.get(opts, :max_keys))

    query = if params != [], do: "?" <> URI.encode_query(params), else: ""

    case request(storage, :get, "/#{bucket}#{query}") do
      {:ok, body} ->
        objects = parse_objects_xml(body)
        {:ok, objects}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get object content"
  @spec get_object(t(), String.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def get_object(storage, bucket, key) do
    request(storage, :get, "/#{bucket}/#{key}")
  end

  @doc "Put object"
  @spec put_object(t(), String.t(), String.t(), binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def put_object(storage, bucket, key, data, opts \\ []) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    case request(storage, :put, "/#{bucket}/#{key}",
           body: data,
           headers: [{"content-type", content_type}]
         ) do
      {:ok, _body, headers} ->
        etag = get_header(headers, "etag") |> String.trim("\"")
        {:ok, etag}

      {:ok, _} ->
        {:ok, ""}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Delete object"
  @spec delete_object(t(), String.t(), String.t()) :: :ok | {:error, term()}
  def delete_object(storage, bucket, key) do
    case request(storage, :delete, "/#{bucket}/#{key}") do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Copy object"
  @spec copy_object(t(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def copy_object(storage, src_bucket, src_key, dst_bucket, dst_key) do
    headers = [{"x-amz-copy-source", "/#{src_bucket}/#{src_key}"}]

    case request(storage, :put, "/#{dst_bucket}/#{dst_key}", headers: headers) do
      {:ok, _body, resp_headers} ->
        etag = get_header(resp_headers, "etag") |> String.trim("\"")
        {:ok, etag}

      {:ok, _} ->
        {:ok, ""}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Check if object exists"
  @spec object_exists?(t(), String.t(), String.t()) :: boolean()
  def object_exists?(storage, bucket, key) do
    case request(storage, :head, "/#{bucket}/#{key}") do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Private functions

  defp request(storage, method, path, opts \\ []) do
    url = "#{storage.endpoint}#{path}"
    body = Keyword.get(opts, :body, "")
    extra_headers = Keyword.get(opts, :headers, [])

    headers = sign_request(storage, method, path, body, extra_headers)

    case :httpc.request(method, {to_charlist(url), headers_to_charlist(headers), 'application/octet-stream', body}, [], []) do
      {:ok, {{_, code, _}, resp_headers, resp_body}} when code in 200..299 ->
        {:ok, to_string(resp_body), resp_headers}

      {:ok, {{_, code, _}, _, resp_body}} ->
        {:error, {:http_error, code, to_string(resp_body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sign_request(storage, method, path, body, extra_headers) do
    if storage.access_key && storage.secret_key do
      now = DateTime.utc_now()
      date_stamp = Calendar.strftime(now, "%Y%m%d")
      amz_date = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")

      payload_hash =
        if body && byte_size(body) > 0 do
          :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
        else
          "UNSIGNED-PAYLOAD"
        end

      host = URI.parse(storage.endpoint).host

      headers =
        [
          {"host", host},
          {"x-amz-date", amz_date},
          {"x-amz-content-sha256", payload_hash}
        ] ++ extra_headers

      signed_headers = headers |> Enum.map(fn {k, _} -> String.downcase(k) end) |> Enum.sort()
      signed_headers_str = Enum.join(signed_headers, ";")

      canonical_headers =
        headers
        |> Enum.sort_by(fn {k, _} -> String.downcase(k) end)
        |> Enum.map(fn {k, v} -> "#{String.downcase(k)}:#{v}\n" end)
        |> Enum.join()

      canonical_request =
        [
          String.upcase(to_string(method)),
          path,
          "",
          canonical_headers,
          signed_headers_str,
          payload_hash
        ]
        |> Enum.join("\n")

      algorithm = "AWS4-HMAC-SHA256"
      credential_scope = "#{date_stamp}/#{storage.region}/s3/aws4_request"

      string_to_sign =
        [
          algorithm,
          amz_date,
          credential_scope,
          :crypto.hash(:sha256, canonical_request) |> Base.encode16(case: :lower)
        ]
        |> Enum.join("\n")

      k_date = hmac_sha256("AWS4#{storage.secret_key}", date_stamp)
      k_region = hmac_sha256(k_date, storage.region)
      k_service = hmac_sha256(k_region, "s3")
      k_signing = hmac_sha256(k_service, "aws4_request")
      signature = hmac_sha256(k_signing, string_to_sign) |> Base.encode16(case: :lower)

      auth_header =
        "#{algorithm} Credential=#{storage.access_key}/#{credential_scope}, SignedHeaders=#{signed_headers_str}, Signature=#{signature}"

      [{"authorization", auth_header} | headers]
    else
      extra_headers
    end
  end

  defp hmac_sha256(key, data) do
    :crypto.mac(:hmac, :sha256, key, data)
  end

  defp headers_to_charlist(headers) do
    Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)
  end

  defp get_header(headers, name) do
    name_down = String.downcase(name)

    Enum.find_value(headers, "", fn
      {k, v} when is_list(k) ->
        if String.downcase(to_string(k)) == name_down, do: to_string(v)

      {k, v} when is_binary(k) ->
        if String.downcase(k) == name_down, do: v
    end)
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: [{key, value} | params]

  defp parse_buckets_xml(body) do
    # Simple regex parsing
    Regex.scan(~r/<Name>([^<]+)<\/Name>/, body)
    |> Enum.map(fn [_, name] ->
      %Bucket{name: name, created_at: DateTime.utc_now()}
    end)
  end

  defp parse_objects_xml(body) do
    Regex.scan(~r/<Key>([^<]+)<\/Key>.*?<Size>(\d+)<\/Size>.*?<ETag>([^<]+)<\/ETag>/s, body)
    |> Enum.map(fn [_, key, size, etag] ->
      %Object{
        key: key,
        size: String.to_integer(size),
        etag: String.trim(etag, "\""),
        last_modified: DateTime.utc_now()
      }
    end)
  end
end
