defmodule ArgusWeb.DashboardFilter do
  @moduledoc false

  alias Argus.Accounts.Scope
  alias ArgusWeb.DashboardFilter.Store
  alias ArgusWeb.ObligationLive.IndexHelpers, as: Index

  @session_key "dashboard_filters"
  @lifecycles ~w(live completed skipped all)
  @date_filters ~w(dated someday all_dates)
  @sorts ~w(due_asc due_desc title urgency recent)

  def assign_filters(socket, session) do
    filters = load(session, socket.assigns.current_scope)

    socket
    |> Phoenix.Component.assign(:mine?, filters.mine?)
    |> Phoenix.Component.assign(:lifecycle, filters.lifecycle)
    |> Phoenix.Component.assign(:query, filters.query)
    |> Phoenix.Component.assign(:sort, filters.sort)
    |> Phoenix.Component.assign(:date_filter, filters.date_filter)
  end

  def load(session, %Scope{user: %{id: user_id}, entity: %{slug: slug}} = scope) do
    case Map.get(filters_for_user(user_id, session), slug) do
      %{} = saved -> merge_saved(saved, scope)
      _ -> defaults(scope)
    end
  end

  def persist(socket) do
    %Scope{user: %{id: user_id}, entity: %{slug: slug}} = socket.assigns.current_scope

    entry = current_entry(socket)
    filters = Store.get(user_id) |> Map.put(slug, entry)
    Store.put(user_id, filters)

    Phoenix.LiveView.push_event(socket, "store-dashboard-filter", %{
      entity_slug: slug,
      mine: entry["mine"],
      lifecycle: entry["lifecycle"],
      query: entry["query"],
      sort: entry["sort"],
      date_filter: entry["date_filter"]
    })
  end

  def merge_session(existing, slug, params) when is_binary(slug) do
    Map.put(existing || %{}, slug, session_entry(params))
  end

  def put_session(conn, slug, params) when is_binary(slug) do
    filters =
      conn
      |> Plug.Conn.get_session(:dashboard_filters)
      |> merge_session(slug, params)

    conn = Plug.Conn.put_session(conn, :dashboard_filters, filters)

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
    session_entry(%{
      "mine" => if(socket.assigns.mine?, do: "true", else: "false"),
      "lifecycle" => Atom.to_string(socket.assigns.lifecycle),
      "query" => socket.assigns.query,
      "sort" => Atom.to_string(socket.assigns.sort),
      "date_filter" => Atom.to_string(socket.assigns.date_filter)
    })
  end

  defp session_entry(params) do
    %{
      "mine" => param_mine(params["mine"]),
      "lifecycle" => param_lifecycle(params["lifecycle"]),
      "query" => param_query(params["query"]),
      "sort" => param_sort(params["sort"]),
      "date_filter" => param_date_filter(params["date_filter"])
    }
  end

  defp merge_saved(%{"mine" => mine, "lifecycle" => lifecycle, "query" => query} = saved, scope) do
    defaults = defaults(scope)

    %{
      mine?: parse_mine(mine, defaults.mine?),
      lifecycle: Index.parse_lifecycle(lifecycle),
      query: query || "",
      sort: parse_sort(Map.get(saved, "sort")),
      date_filter: parse_date_filter(Map.get(saved, "date_filter"))
    }
  end

  defp merge_saved(_, scope), do: defaults(scope)

  defp defaults(%Scope{} = scope) do
    %{
      mine?: Index.default_mine?(scope),
      lifecycle: :live,
      query: "",
      sort: :due_asc,
      date_filter: :dated
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
  defp parse_sort(_), do: :due_asc

  defp param_date_filter(df) when df in @date_filters, do: df
  defp param_date_filter(_), do: "dated"

  defp parse_date_filter("someday"), do: :someday
  defp parse_date_filter("all_dates"), do: :all_dates
  defp parse_date_filter(_), do: :dated
end
