defmodule SquirrelDB.Query do
  @moduledoc """
  Query builder for SquirrelDB.
  Uses MongoDB-like naming: find/sort/limit

  ## Example

      import SquirrelDB.Query

      query = table("users")
      |> find(age: {:gt, 21})
      |> sort("name")
      |> limit(10)
      |> compile()
  """

  defstruct table_name: nil,
            filter_expr: nil,
            sort_specs: [],
            limit_value: nil,
            skip_value: nil,
            is_changes: false

  @type t :: %__MODULE__{
          table_name: String.t(),
          filter_expr: String.t() | nil,
          sort_specs: list({String.t(), :asc | :desc}),
          limit_value: non_neg_integer() | nil,
          skip_value: non_neg_integer() | nil,
          is_changes: boolean()
        }

  @doc "Create a table query builder"
  @spec table(String.t()) :: t()
  def table(name), do: %__MODULE__{table_name: name}

  @doc """
  Find documents matching condition.

  ## Operators
  - `{:eq, value}` - equals
  - `{:ne, value}` - not equals
  - `{:gt, value}` - greater than
  - `{:gte, value}` - greater than or equal
  - `{:lt, value}` - less than
  - `{:lte, value}` - less than or equal
  - `{:in, [values]}` - value in list
  - `{:not_in, [values]}` - value not in list
  - `{:contains, value}` - string contains
  - `{:starts_with, value}` - string starts with
  - `{:ends_with, value}` - string ends with
  - `{:exists, boolean}` - field exists

  ## Examples

      query |> find(age: {:gt, 21})
      query |> find(status: "active", role: "admin")
      query |> find([{:and, [age: {:gt, 21}, status: "active"]}])
  """
  @spec find(t(), keyword() | map()) :: t()
  def find(query, conditions) do
    %{query | filter_expr: compile_filter(conditions)}
  end

  @doc "Sort by field"
  @spec sort(t(), String.t(), :asc | :desc) :: t()
  def sort(query, field, direction \\ :asc) do
    %{query | sort_specs: query.sort_specs ++ [{to_string(field), direction}]}
  end

  @doc "Limit number of results"
  @spec limit(t(), non_neg_integer()) :: t()
  def limit(query, n), do: %{query | limit_value: n}

  @doc "Skip results (offset)"
  @spec skip(t(), non_neg_integer()) :: t()
  def skip(query, n), do: %{query | skip_value: n}

  @doc "Subscribe to changes"
  @spec changes(t()) :: t()
  def changes(query), do: %{query | is_changes: true}

  @doc "Compile to SquirrelDB JS query string"
  @spec compile(t()) :: String.t()
  def compile(%__MODULE__{} = q) do
    query = ~s{db.table("#{q.table_name}")}

    query =
      if q.filter_expr do
        query <> ".filter(doc => #{q.filter_expr})"
      else
        query
      end

    query =
      Enum.reduce(q.sort_specs, query, fn {field, direction}, acc ->
        case direction do
          :desc -> acc <> ~s{.orderBy("#{field}", "desc")}
          _ -> acc <> ~s{.orderBy("#{field}")}
        end
      end)

    query =
      if q.limit_value do
        query <> ".limit(#{q.limit_value})"
      else
        query
      end

    query =
      if q.skip_value do
        query <> ".skip(#{q.skip_value})"
      else
        query
      end

    if q.is_changes do
      query <> ".changes()"
    else
      query <> ".run()"
    end
  end

  # Compile filter conditions to JS
  defp compile_filter(conditions) when is_list(conditions) or is_map(conditions) do
    conditions
    |> Enum.map(&compile_condition/1)
    |> Enum.join(" && ")
    |> case do
      "" -> "true"
      expr -> expr
    end
  end

  defp compile_condition({:and, conditions}) do
    parts = Enum.map(conditions, &compile_condition/1)
    "(#{Enum.join(parts, " && ")})"
  end

  defp compile_condition({:or, conditions}) do
    parts = Enum.map(conditions, &compile_condition/1)
    "(#{Enum.join(parts, " || ")})"
  end

  defp compile_condition({:not, condition}) do
    "!(#{compile_condition(condition)})"
  end

  defp compile_condition({field, {:eq, value}}) do
    "doc.#{field} === #{Jason.encode!(value)}"
  end

  defp compile_condition({field, {:ne, value}}) do
    "doc.#{field} !== #{Jason.encode!(value)}"
  end

  defp compile_condition({field, {:gt, value}}) do
    "doc.#{field} > #{value}"
  end

  defp compile_condition({field, {:gte, value}}) do
    "doc.#{field} >= #{value}"
  end

  defp compile_condition({field, {:lt, value}}) do
    "doc.#{field} < #{value}"
  end

  defp compile_condition({field, {:lte, value}}) do
    "doc.#{field} <= #{value}"
  end

  defp compile_condition({field, {:in, values}}) do
    "#{Jason.encode!(values)}.includes(doc.#{field})"
  end

  defp compile_condition({field, {:not_in, values}}) do
    "!#{Jason.encode!(values)}.includes(doc.#{field})"
  end

  defp compile_condition({field, {:contains, value}}) do
    "doc.#{field}.includes(#{Jason.encode!(value)})"
  end

  defp compile_condition({field, {:starts_with, value}}) do
    "doc.#{field}.startsWith(#{Jason.encode!(value)})"
  end

  defp compile_condition({field, {:ends_with, value}}) do
    "doc.#{field}.endsWith(#{Jason.encode!(value)})"
  end

  defp compile_condition({field, {:exists, true}}) do
    "doc.#{field} !== undefined"
  end

  defp compile_condition({field, {:exists, false}}) do
    "doc.#{field} === undefined"
  end

  defp compile_condition({field, value}) do
    # Direct equality
    "doc.#{field} === #{Jason.encode!(value)}"
  end
end
