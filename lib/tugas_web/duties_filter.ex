defmodule TugasWeb.DutiesFilter do
  @moduledoc false

  alias Tugas.Accounts.Scope
  alias TugasWeb.DutiesFilter.Store
  alias TugasWeb.DutyLive.IndexHelpers, as: Index

  @sid_key "filter_sid"
  @lifecycles ~w(live completed skipped all)
  @sorts ~w(due_asc due_desc title urgency someday)

  @doc "Generate an opaque per-browser filter session id."
  def new_sid, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  def assign_filters(socket, session) do
    socket
    |> assign_sid(session)
    |> assign_from_filters(load(session, socket.assigns.current_scope))
  end

  @doc "Stash the per-browser filter session id in assigns so `persist/1` can write to it."
  def assign_sid(socket, session) do
    Phoenix.Component.assign(socket, :filter_sid, sid(session))
  end

  def assign_from_filters(socket, filters) do
    socket
    |> Phoenix.Component.assign(:mine?, filters.mine?)
    |> Phoenix.Component.assign(:lifecycle, filters.lifecycle)
    |> Phoenix.Component.assign(:query, filters.query)
    |> Phoenix.Component.assign(:sort, filters.sort)
  end

  def load(session, %Scope{entity: %{slug: slug}} = scope) do
    saved = session |> sid() |> Store.get() |> Map.get(slug)

    case saved do
      %{} = entry -> merge_saved(entry, scope)
      _ -> defaults(scope)
    end
  end

  def persist(socket) do
    %{filter_sid: sid, current_scope: %Scope{entity: %{slug: slug}}} = socket.assigns

    store = Store.get(sid)
    prior = Map.get(store, slug, %{})
    entry = Map.merge(prior, current_entry(socket))
    Store.put(sid, Map.put(store, slug, entry))

    socket
  end

  defp sid(session), do: get_in(session, [@sid_key])

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
