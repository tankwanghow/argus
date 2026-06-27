defmodule TugasWeb.MobileLive.Components do
  @moduledoc """
  Shared presentational components for the mobile (`/m/:entity_slug`) UI.
  """
  use TugasWeb, :html

  @doc """
  A touch-friendly duty card linking to the mobile show page, with a
  left accent and urgency badge sized for field use.
  """
  attr :id, :string, required: true
  attr :row, :map, required: true, doc: "%{duty: ..., urgency: ..., cycle_status: ...}"
  attr :today, Date, required: true
  attr :slug, :string, required: true
  attr :timezone, :string, default: nil

  def duty_card(assigns) do
    ~H"""
    <li
      id={@id}
      data-event-count={@row.event_count}
      data-event-status={@row.latest_event && @row.latest_event.status}
    >
      <.link
        navigate={~p"/m/#{@slug}/duties/#{@row.duty.id}"}
        class={["block rounded-box border border-base-300 p-3 border-l-4", accent(@row)]}
      >
        <div class="flex items-center mb-1 justify-between gap-1">
          <div class="font-medium truncate max-w-[15rem]">{@row.duty.title}</div>
          <.cycle_badge
            cycle_status={@row.cycle_status}
            tier={@row.tier}
            duty={@row.duty}
            today={@today}
            timezone={@timezone}
            in_error={!is_nil(@row.duty.completed_in_error_at)}
          />
        </div>
        <div class="flex flex-wrap text-xs gap-0.5 -space-y-1">
          <div class="text-info">{@row.duty.duty_type.name}</div>
          <div :if={@row.duty.due_by}>·</div>
          <div :if={@row.duty.due_by} class="text-base-content/60">
            due {format_date(@row.duty.due_by, :short)}
          </div>
          <div>·</div>
          {assignee_label(@row.duty.primary_assignee)}
        </div>
        <.event_meta
          :if={@row.latest_event}
          event={@row.latest_event}
          event_count={@row.event_count}
          show_actor={false}
        />
      </.link>
    </li>
    """
  end

  defp accent(%{cycle_status: status}) when status in [:skipped, :series_ended],
    do: "border-error/60"

  defp accent(%{cycle_status: :completed}), do: "border-success/60"
  defp accent(%{cycle_status: :live, duty: %{due_by: nil}}), do: "border-base-300"
  defp accent(%{tier: tier}), do: tier_border(tier)
  defp accent(_), do: "border-transparent"

  defp assignee_label(assigns) when assigns == nil do
    ~H"""
    <div class="text-error">Unassigned</div>
    """
  end

  defp assignee_label(assigns) do
    ~H"""
    <div class="text-primary">{user_label(assigns)}</div>
    """
  end
end
