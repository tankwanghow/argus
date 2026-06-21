defmodule ArgusWeb.ObligationLive.IndexHelpers do
  @moduledoc false

  alias Argus.Accounts.Scope
  alias Argus.Obligations
  alias Argus.Obligations.{Obligation, Urgency}

  @urgency_rank %{overdue: 0, due_soon: 1, ok: 2}
  @lifecycles ~w(live completed skipped all)a

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

  def load_rows(scope, today, mine?, lifecycle, query) do
    status = status_atom(mine?, lifecycle)
    obligations = Obligations.list_obligations(scope, status: status, query: query)
    summaries = Obligations.event_summaries_for(obligations)

    obligations
    |> Enum.map(fn obligation ->
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
    |> sort_rows(lifecycle)
  end

  defp sort_rows(rows, :live) do
    Enum.sort_by(rows, fn %{obligation: o, urgency: u} -> {@urgency_rank[u], o.due_by} end)
  end

  defp sort_rows(rows, _lifecycle), do: rows

  def cycle_status(%Obligation{completed_at: %DateTime{}}), do: :completed
  def cycle_status(%Obligation{series_ended_at: %DateTime{}}), do: :series_ended
  def cycle_status(%Obligation{closed_at: %DateTime{}}), do: :skipped
  def cycle_status(_), do: :live
end
