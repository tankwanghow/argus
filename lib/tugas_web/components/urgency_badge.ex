defmodule TugasWeb.UrgencyBadge do
  @moduledoc """
  Graded urgency helpers for obligations: the countdown text and the matching
  left-accent border class, both keyed off `Tugas.Obligations.Urgency.tier/3`.
  The countdown is rendered by `TugasWeb.CycleBadge`; the border by the dashboards.
  """

  @doc "Left-accent border class for a graded urgency tier."
  def tier_border(:overdue), do: "border-error"
  def tier_border(:critical), do: "border-error/60"
  def tier_border(:due_soon), do: "border-warning"
  def tier_border(:approaching), do: "border-warning/40"
  def tier_border(_), do: "border-transparent"

  @doc "Countdown text for a tier, or nil when on track."
  def badge_text(:ok, _due_by, _today), do: nil

  def badge_text(_tier, nil, _today), do: nil

  def badge_text(:overdue, due_by, today), do: "#{Date.diff(today, due_by)}d overdue"

  def badge_text(_tier, due_by, today) do
    case Date.diff(due_by, today) do
      0 -> "Due today"
      days -> "#{days}d left"
    end
  end
end
