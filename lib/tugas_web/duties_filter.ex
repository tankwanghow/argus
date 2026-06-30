defmodule TugasWeb.DutiesFilter do
  @moduledoc false

  alias Tugas.Accounts.Scope
  alias TugasWeb.DutiesFilter.Store
  alias TugasWeb.DutyLive.IndexHelpers, as: Index

  @session_key "duties_filters"
  @lifecycles ~w(live completed skipped all)
  @sorts ~w(due_asc due_desc title urgency someday)

  def assign_filters(socket, session) do
    assign_from_filters(socket, load(session, socket.assigns.current_scope))
  end

  def assign_from_filters(socket, filters) do
    socket
    |> Phoenix.Component.assign(:mine?, filters.mine?)
    |> Phoenix.Component.assign(:lifecycle, filters.lifecycle)
    |> Phoenix.Component.assign(:query, filters.query)
    |> Phoenix.Component.assign(:sort, filters.sort)
  end

  def load(session, %Scope{user: %{id: user_id}, entity: %{slug: slug}} = scope) do
    case Map.get(filters_for_user(user_id, session), slug) do
      %{} = saved -> merge_saved(saved, scope)
      _ -> defaults(scope)
    end
  end

  def persist(socket) do
    %Scope{user: %{id: user_id}, entity: %{slug: slug}} = socket.assigns.current_scope

    store = Store.get(user_id)
    prior = Map.get(store, slug, %{})
    entry = Map.merge(prior, current_entry(socket))
    Store.put(user_id, Map.put(store, slug, entry))

    Phoenix.LiveView.push_event(socket, "store-duties-filter", store_event_payload(slug, entry))
  end

  def merge_session(existing, slug, params) when is_binary(slug) do
    prior = get_in(existing, [slug]) || %{}
    Map.put(existing || %{}, slug, Map.merge(prior, session_entry(params)))
  end

  def put_session(conn, slug, params) when is_binary(slug) do
    filters =
      conn
      |> Plug.Conn.get_session(:duties_filters)
      |> merge_session(slug, params)

    conn = Plug.Conn.put_session(conn, :duties_filters, filters)

    if user_id = user_id(conn) do
      Store.put(user_id, filters)
    end

    conn
  end

  defp filters_for_user(user_id, session) do
    store = Store.get(user_id)
    session_filters = get_in(session, [@session_key]) || %{}

    cond do
      store != %{} ->
        store

      session_filters != %{} ->
        Store.put(user_id, session_filters)
        session_filters

      true ->
        %{}
    end
  end

  defp current_entry(socket) do
    params = %{
      "mine" => if(socket.assigns.mine?, do: "true", else: "false"),
      "lifecycle" => Atom.to_string(socket.assigns.lifecycle),
      "query" => socket.assigns.query,
      "sort" => Atom.to_string(socket.assigns.sort)
    }

    params =
      if Map.has_key?(socket.assigns, :year) and Map.has_key?(socket.assigns, :month) do
        Map.merge(params, %{
          "year" => Integer.to_string(socket.assigns.year),
          "month" => Integer.to_string(socket.assigns.month)
        })
      else
        params
      end

    session_entry(params)
  end

  defp session_entry(params) do
    %{
      "mine" => param_mine(params["mine"]),
      "lifecycle" => param_lifecycle(params["lifecycle"]),
      "query" => param_query(params["query"]),
      "sort" => param_sort(params["sort"])
    }
    |> maybe_put_calendar_month(params)
  end

  defp store_event_payload(slug, entry) do
    payload = %{
      entity_slug: slug,
      mine: entry["mine"],
      lifecycle: entry["lifecycle"],
      query: entry["query"],
      sort: entry["sort"]
    }

    case {entry["year"], entry["month"]} do
      {year, month} when is_binary(year) and is_binary(month) ->
        Map.merge(payload, %{year: year, month: month})

      _ ->
        payload
    end
  end

  defp merge_saved(%{"mine" => mine, "lifecycle" => lifecycle, "query" => query} = saved, scope) do
    defaults = defaults(scope)

    %{
      mine?: parse_mine(mine, defaults.mine?),
      lifecycle: Index.parse_lifecycle(lifecycle),
      query: query || "",
      sort: parse_sort(Map.get(saved, "sort")),
      year: parse_year(Map.get(saved, "year")),
      month: parse_month(Map.get(saved, "month"))
    }
  end

  defp merge_saved(_, scope), do: defaults(scope)

  defp defaults(%Scope{} = scope) do
    %{
      mine?: Index.default_mine?(scope),
      lifecycle: :live,
      query: "",
      sort: :due_asc,
      year: nil,
      month: nil
    }
  end

  defp user_id(%Plug.Conn{assigns: %{current_scope: %Scope{user: %{id: id}}}}), do: id
  defp user_id(_), do: nil

  defp parse_mine(value, default) do
    case parse_mine(value) do
      nil -> default
      bool -> bool
    end
  end

  defp parse_mine(true), do: true
  defp parse_mine(false), do: false
  defp parse_mine("true"), do: true
  defp parse_mine("false"), do: false
  defp parse_mine(_), do: nil

  defp param_mine("true"), do: "true"
  defp param_mine("false"), do: "false"
  defp param_mine(true), do: "true"
  defp param_mine(false), do: "false"
  defp param_mine(_), do: "false"

  defp param_lifecycle(lifecycle) when lifecycle in @lifecycles, do: lifecycle
  defp param_lifecycle(_), do: "live"

  defp param_query(query) when is_binary(query), do: query
  defp param_query(_), do: ""

  defp param_sort(sort) when sort in @sorts, do: sort
  defp param_sort(_), do: "due_asc"

  defp parse_sort("due_desc"), do: :due_desc
  defp parse_sort("title"), do: :title
  defp parse_sort("urgency"), do: :urgency
  defp parse_sort("someday"), do: :someday
  defp parse_sort(_), do: :due_asc

  defp maybe_put_calendar_month(entry, params) do
    case {parse_year(params["year"]), parse_month(params["month"])} do
      {year, month} when not is_nil(year) and not is_nil(month) ->
        Map.merge(entry, %{
          "year" => Integer.to_string(year),
          "month" => Integer.to_string(month)
        })

      _ ->
        entry
    end
  end

  defp parse_year(year) when is_integer(year) and year >= 1970 and year <= 2100, do: year

  defp parse_year(year) when is_binary(year) do
    case Integer.parse(year) do
      {parsed, ""} -> parse_year(parsed)
      _ -> nil
    end
  end

  defp parse_year(_), do: nil

  defp parse_month(month) when is_integer(month) and month in 1..12, do: month

  defp parse_month(month) when is_binary(month) do
    case Integer.parse(month) do
      {parsed, ""} -> parse_month(parsed)
      _ -> nil
    end
  end

  defp parse_month(_), do: nil
end
