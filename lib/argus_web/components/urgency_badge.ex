defmodule ArgusWeb.UrgencyBadge do
  @moduledoc """
  Graded urgency UI for obligations: a countdown badge and the matching
  left-accent border class, both keyed off `Argus.Obligations.Urgency.tier/3`.
  """
  use Phoenix.Component

  @doc """
  Renders a countdown badge ("3d left", "Due today", "2d overdue") coloured by
  tier. Nothing renders for the `:ok` tier (on track).
  """
  attr :tier, :atom, required: true
  attr :due_by, :any, required: true
  attr :today, :any, required: true

  def urgency_badge(assigns) do
    assigns =
      assigns
      |> assign(:text, badge_text(assigns.tier, assigns.due_by, assigns.today))
      |> assign(:class, badge_class(assigns.tier))

    ~H"""
    <span :if={@text} class={["badge badge-sm", @class]} data-urgency={@tier}>
      {@text}
    </span>
    """
  end

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

  @doc "daisyUI badge class for a tier."
  def badge_class(:overdue), do: "badge-error"
  def badge_class(:critical), do: "badge-error badge-soft"
  def badge_class(:due_soon), do: "badge-warning"
  def badge_class(:approaching), do: "badge-warning badge-soft"
  def badge_class(_), do: ""
end
