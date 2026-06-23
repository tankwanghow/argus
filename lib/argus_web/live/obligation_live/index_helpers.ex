defmodule ArgusWeb.ObligationLive.IndexHelpers do
  @moduledoc false

  alias Argus.Accounts.Scope
  alias Argus.Obligations
  alias Argus.Obligations.{Obligation, Urgency}

  @lifecycles ~w(live completed skipped all)a
  @page_size 25

  @doc "Lifecycle options for the status dropdown, as `{value, label}` pairs."
  def lifecycles, do: Enum.map(@lifecycles, &{Atom.to_string(&1), lifecycle_label(&1)})

  @doc "Whether the list defaults to the current user's own work."
  def default_mine?(%Scope{role: :member}), do: true
  def default_mine?(_scope), do: false

  def parse_lifecycle("completed"), do: :completed
  def parse_lifecycle("skipped"), do: :skipped
  def parse_lifecycle("all"), do: :all
  def parse_lifecycle(_), do: :live

  def lifecycle_label(:live), do: "Live"
  def lifecycle_label(:completed), do: "Completed"
  def lifecycle_label(:skipped), do: "Skipped"
  def lifecycle_label(:all), do: "All"

  @doc "Combined status atom for `Obligations.list_obligations/2`."
  def status_atom(true, :live), do: :my_live
  def status_atom(true, :completed), do: :my_completed
  def status_atom(true, :skipped), do: :my_skipped
  def status_atom(true, :all), do: :my_all
  def status_atom(false, lifecycle), do: lifecycle

  def empty_message(mine?, lifecycle) do
    who = if mine?, do: " assigned to you", else: ""

    case lifecycle do
      :live -> "No live duties#{who}."
      :completed -> "No completed duties#{who}."
      :skipped -> "No skipped duties#{who}."
      :all -> "No duties#{who}."
    end
  end

  @doc "Sort options for the dropdown; urgency is offered only on the live lifecycle."
  def sorts(:live),
    do: [
      {"due_asc", "Due soonest"},
      {"due_desc", "Due latest"},
      {"urgency", "Most urgent"},
      {"title", "Title A–Z"}
    ]

  def sorts(_lifecycle),
    do: [{"due_asc", "Due soonest"}, {"due_desc", "Due latest"}, {"title", "Title A–Z"}]

  def parse_sort("due_desc"), do: :due_desc
  def parse_sort("title"), do: :title
  def parse_sort("urgency"), do: :urgency
  def parse_sort(_), do: :due_asc

  def effective_sort(:urgency, :live), do: :urgency
  def effective_sort(:urgency, _lifecycle), do: :due_asc
  def effective_sort(sort, _lifecycle), do: sort

  def load_rows(scope, today, mine?, lifecycle, query) do
    status = status_atom(mine?, lifecycle)

    scope
    |> Obligations.list_obligations(status: status, query: query)
    |> build_rows(today)
  end

  def load_page(scope, today, mine?, lifecycle, query, sort, cursor) do
    status = status_atom(mine?, lifecycle)
    do_load_page(scope, today, status, lifecycle, query, effective_sort(sort, lifecycle), cursor)
  end

  # Non-urgency (and non-live urgency, already downgraded): straight SQL paging.
  defp do_load_page(scope, today, status, _lifecycle, query, sort, cursor)
       when sort != :urgency do
    page =
      Obligations.list_obligations_page(scope,
        status: status,
        query: query,
        sort: sort,
        cursor: cursor,
        limit: @page_size
      )

    %{rows: build_rows(page.rows, today), cursor: page.cursor, end?: page.end?}
  end

  defp build_rows(obligations, today) do
    summaries = Obligations.event_summaries_for(obligations)

    Enum.map(obligations, fn obligation ->
      %{event_count: event_count, latest_event: latest_event} =
        Map.fetch!(summaries, obligation.id)

      %{
        obligation: obligation,
        cycle_status: cycle_status(obligation),
        urgency: Urgency.classify(obligation.obligation_type, obligation.due_by, today),
        tier: Urgency.tier(obligation.obligation_type, obligation.due_by, today),
        event_count: event_count,
        latest_event: latest_event
      }
    end)
  end

  def cycle_status(%Obligation{completed_at: %DateTime{}}), do: :completed
  def cycle_status(%Obligation{series_ended_at: %DateTime{}}), do: :series_ended
  def cycle_status(%Obligation{closed_at: %DateTime{}}), do: :skipped
  def cycle_status(_), do: :live
end
