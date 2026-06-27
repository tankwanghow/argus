defmodule TugasWeb.CycleBadge do
  @moduledoc """
  The single badge shown top-right on dashboard rows, mobile cards, and the show
  pages. One consistent pill that adapts to the obligation cycle:

    * live → the urgency countdown ("3d overdue" / "Due today" / "5d left"),
      coloured by tier; nothing when on-track or undated
    * terminal → the status word and its date ("Completed 22 Mar 2026")

  Only the colour varies between states. Urgency text comes from
  `TugasWeb.UrgencyBadge.badge_text/3`.
  """
  use Phoenix.Component

  alias TugasWeb.UrgencyBadge

  attr :cycle_status, :atom, required: true
  attr :tier, :atom, default: :ok
  attr :obligation, :any, required: true
  attr :today, :any, required: true
  attr :timezone, :string, default: nil
  attr :in_error, :boolean, default: false

  def cycle_badge(assigns) do
    assigns = assign(assigns, :badge, badge(assigns))

    ~H"""
    <div
      :if={@badge}
      class={[
        "text-center gap-0.5 rounded border px-2 py-0.5 text-xs font-medium",
        @badge.color
      ]}
      data-cycle={@cycle_status}
      data-urgency={@cycle_status == :live && @tier}
    >
      <div>{@badge.label}</div>
      <div :if={@badge.date} class="font-normal opacity-80">{@badge.date}</div>
    </div>
    """
  end

  defp badge(%{cycle_status: :completed, in_error: true, obligation: o, timezone: tz}),
    do: %{color: "bg-error", label: "Completed error", date: fmt(o.completed_at, tz)}

  defp badge(%{cycle_status: :completed, obligation: o, timezone: tz}),
    do: %{color: "bg-success", label: "Completed", date: fmt(o.completed_at, tz)}

  defp badge(%{cycle_status: :skipped, obligation: o, timezone: tz}),
    do: %{color: "bg-warning", label: "Skipped", date: fmt(o.closed_at, tz)}

  defp badge(%{cycle_status: :series_ended, obligation: o, timezone: tz}),
    do: %{color: "border-warning text-warning", label: "Series ended", date: fmt(o.closed_at, tz)}

  # A live duty with no due date is workable "anytime" — show a green badge
  # rather than the (date-driven) urgency countdown.
  defp badge(%{cycle_status: :live, obligation: %{due_by: nil}}),
    do: %{color: "border-success text-success", label: "Anytime", date: nil}

  defp badge(%{cycle_status: :live, tier: tier, obligation: o, today: today}) do
    case UrgencyBadge.badge_text(tier, o.due_by, today) do
      nil -> nil
      text -> %{color: urgency_color(tier), label: text, date: nil}
    end
  end

  defp badge(_), do: nil

  defp urgency_color(tier) when tier in [:overdue, :critical], do: "border-error text-error"
  defp urgency_color(_tier), do: "border-warning text-warning"

  defp fmt(%DateTime{} = dt, timezone),
    do: TugasWeb.CoreComponents.format_zoned_date(dt, timezone, :short)

  defp fmt(_, _), do: nil
end
