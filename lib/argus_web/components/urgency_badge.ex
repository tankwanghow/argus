defmodule ArgusWeb.UrgencyBadge do
  @moduledoc """
  Renders overdue / due-soon urgency badges for obligations.
  """
  use Phoenix.Component

  attr :urgency, :atom, required: true

  def urgency_badge(assigns) do
    ~H"""
    <span
      :if={@urgency == :overdue}
      class="badge badge-error badge-sm"
      data-urgency="overdue"
    >
      Overdue
    </span>
    <span
      :if={@urgency == :due_soon}
      class="badge badge-warning badge-sm"
      data-urgency="due_soon"
    >
      Due soon
    </span>
    """
  end
end