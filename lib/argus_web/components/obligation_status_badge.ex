defmodule ArgusWeb.ObligationStatusBadge do
  @moduledoc """
  Renders completed / cancelled badges for non-live obligation cycles.
  """
  use Phoenix.Component

  attr :cycle_status, :atom, required: true

  def obligation_status_badge(assigns) do
    ~H"""
    <span :if={@cycle_status == :completed} class="badge badge-success badge-sm">Completed</span>
    <span :if={@cycle_status == :cancelled} class="badge badge-error badge-sm">Cancelled</span>
    """
  end
end
