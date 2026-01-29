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
            filter_conditions: nil,
            sort_specs: [],
            limit_value: nil,
            skip_value: nil,
            is_changes: false

  @type t :: %__MODULE__{
          table_name: String.t(),
          filter_expr: String.t() | nil,
          filter_conditions: keyword() | map() | nil,
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
    %{query | filter_expr: compile_filter(conditions), filter_conditions: conditions}
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

  @doc "Compile to SquirrelDB JS query string (legacy)"
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

  @doc "Compile to structured query map (preferred, no JS evaluation on server)"
  @spec compile_structured(t()) :: map()
  def compile_structured(%__MODULE__{} = q) do
    query = %{"table" => q.table_name}

    query =
      if q.filter_conditions do
        Map.put(query, "filter", filter_to_structured(q.filter_conditions))
      else
        query
      end

    query =
      if q.sort_specs != [] do
        sort = Enum.map(q.sort_specs, fn {field, direction} ->
          %{"field" => field, "direction" => to_string(direction)}
        end)
        Map.put(query, "sort", sort)
      else
        query
      end

    query = if q.limit_value, do: Map.put(query, "limit", q.limit_value), else: query
    query = if q.skip_value, do: Map.put(query, "skip", q.skip_value), else: query

    if q.is_changes do
      Map.put(query, "changes", %{"includeInitial" => false})
    else
      query
    end
  end

  # Convert filter conditions to structured format
  defp filter_to_structured(conditions) when is_list(conditions) or is_map(conditions) do
    conditions
    |> Enum.map(&condition_to_structured/1)
    |> Enum.into(%{})
  end

  defp condition_to_structured({:and, conditions}) do
    {"$and", Enum.map(conditions, &filter_to_structured([&1]))}
  end

  defp condition_to_structured({:or, conditions}) do
    {"$or", Enum.map(conditions, &filter_to_structured([&1]))}
  end

  defp condition_to_structured({:not, condition}) do
    {"$not", filter_to_structured([condition])}
  end

  defp condition_to_structured({field, {:eq, value}}), do: {to_string(field), %{"$eq" => value}}
  defp condition_to_structured({field, {:ne, value}}), do: {to_string(field), %{"$ne" => value}}
  defp condition_to_structured({field, {:gt, value}}), do: {to_string(field), %{"$gt" => value}}
  defp condition_to_structured({field, {:gte, value}}), do: {to_string(field), %{"$gte" => value}}
  defp condition_to_structured({field, {:lt, value}}), do: {to_string(field), %{"$lt" => value}}
  defp condition_to_structured({field, {:lte, value}}), do: {to_string(field), %{"$lte" => value}}
  defp condition_to_structured({field, {:in, values}}), do: {to_string(field), %{"$in" => values}}
  defp condition_to_structured({field, {:not_in, values}}), do: {to_string(field), %{"$nin" => values}}
  defp condition_to_structured({field, {:contains, value}}), do: {to_string(field), %{"$contains" => value}}
  defp condition_to_structured({field, {:starts_with, value}}), do: {to_string(field), %{"$startsWith" => value}}
  defp condition_to_structured({field, {:ends_with, value}}), do: {to_string(field), %{"$endsWith" => value}}
  defp condition_to_structured({field, {:exists, value}}), do: {to_string(field), %{"$exists" => value}}
  defp condition_to_structured({field, value}), do: {to_string(field), %{"$eq" => value}}

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
