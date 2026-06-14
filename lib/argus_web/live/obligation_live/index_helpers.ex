defmodule ArgusWeb.ObligationLive.IndexHelpers do
  @moduledoc false

  alias Argus.Obligations
  alias Argus.Obligations.{Obligation, Urgency}

  @urgency_rank %{overdue: 0, due_soon: 1, ok: 2}
  @statuses ~w(live completed cancelled all)

  def statuses, do: @statuses

  def parse_status("completed"), do: :completed
  def parse_status("cancelled"), do: :cancelled
  def parse_status("all"), do: :all
  def parse_status(_), do: :live

  def status_label(:live), do: "Live"
  def status_label(:completed), do: "Completed"
  def status_label(:cancelled), do: "Cancelled"
  def status_label(:all), do: "All"

  def empty_message(:live), do: "No live obligations."
  def empty_message(:completed), do: "No completed obligations."
  def empty_message(:cancelled), do: "No cancelled obligations."
  def empty_message(:all), do: "No obligations."

  def load_rows(scope, today, status, query) do
    scope
    |> Obligations.list_obligations(status: status, query: query)
    |> Enum.map(fn obligation ->
      %{
        obligation: obligation,
        cycle_status: cycle_status(obligation),
        urgency: Urgency.classify(obligation.obligation_type, obligation.due_by, today)
      }
    end)
    |> sort_rows(status)
  end

  defp sort_rows(rows, :live) do
    Enum.sort_by(rows, fn %{obligation: o, urgency: u} -> {@urgency_rank[u], o.due_by} end)
  end

  defp sort_rows(rows, _status) do
    rows
  end

  def cycle_status(%Obligation{status: "cancelled"}), do: :cancelled

  def cycle_status(%Obligation{completed_at: %DateTime{}}), do: :completed

  def cycle_status(_), do: :live
end
