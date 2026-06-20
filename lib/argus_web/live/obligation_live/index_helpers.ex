defmodule ArgusWeb.ObligationLive.IndexHelpers do
  @moduledoc false

  alias Argus.Accounts.Scope
  alias Argus.Obligations
  alias Argus.Obligations.{Obligation, Urgency}

  @urgency_rank %{overdue: 0, due_soon: 1, ok: 2}
  @statuses ~w(my_live my_completed live completed skipped all)

  def statuses, do: @statuses

  def default_status(%Scope{role: :member}), do: :my_live
  def default_status(_scope), do: :live

  def parse_status("my_live"), do: :my_live
  def parse_status("my_completed"), do: :my_completed
  def parse_status("completed"), do: :completed
  def parse_status("skipped"), do: :skipped
  def parse_status("all"), do: :all
  def parse_status(_), do: :live

  def status_label(:my_live), do: "My Live"
  def status_label(:my_completed), do: "My Completed"
  def status_label(:live), do: "Live"
  def status_label(:completed), do: "Completed"
  def status_label(:skipped), do: "Skipped"
  def status_label(:all), do: "All"

  def empty_message(:my_live), do: "No live obligations assigned to you."
  def empty_message(:my_completed), do: "No completed obligations assigned to you."
  def empty_message(:live), do: "No live obligations."
  def empty_message(:completed), do: "No completed obligations."
  def empty_message(:skipped), do: "No skipped obligations."
  def empty_message(:all), do: "No obligations."

  def load_rows(scope, today, status, query) do
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
    |> sort_rows(status)
  end

  defp sort_rows(rows, status) when status in [:live, :my_live] do
    Enum.sort_by(rows, fn %{obligation: o, urgency: u} -> {@urgency_rank[u], o.due_by} end)
  end

  defp sort_rows(rows, _status) do
    rows
  end

  def cycle_status(%Obligation{completed_at: %DateTime{}}), do: :completed
  def cycle_status(%Obligation{series_ended_at: %DateTime{}}), do: :series_ended
  def cycle_status(%Obligation{closed_at: %DateTime{}}), do: :skipped
  def cycle_status(_), do: :live
end
