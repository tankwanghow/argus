defmodule TugasWeb.DutyCalendar do
  @moduledoc false
  use Phoenix.Component

  import TugasWeb.UrgencyBadge, only: [tier_border: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: TugasWeb.Endpoint,
    router: TugasWeb.Router,
    statics: TugasWeb.static_paths()

  alias TugasWeb.DashboardLive.CalendarHelpers

  attr :grid, :map, required: true
  attr :grouped, :map, required: true
  attr :someday_rows, :list, required: true
  attr :slug, :string, required: true
  attr :day_modal_date, :any, default: nil
  attr :day_modal_rows, :list, default: []
  attr :someday_modal_open?, :boolean, default: false

  def duty_calendar(assigns) do
    ~H"""
    <div id="duty-calendar" class="space-y-4">
      <div class="grid grid-cols-7 gap-px bg-base-300 rounded-lg overflow-hidden border border-base-300">
        <div
          :for={label <- ~w(Sun Mon Tue Wed Thu Fri Sat)}
          class="bg-base-200 px-2 py-1.5 text-center text-xs font-semibold text-base-content/70"
        >
          {label}
        </div>
        <div
          :for={cell <- @grid.weeks |> List.flatten()}
          id={"calendar-day-#{cell.date}"}
          class={[
            "bg-base-100 min-h-24 p-1 space-y-0.5",
            !cell.in_month? && "bg-base-200/40 text-base-content/40",
            cell.today? && "ring-2 ring-inset ring-primary/40"
          ]}
        >
          <div class="text-xs font-medium px-0.5">{cell.date.day}</div>
          <%= for {row, idx} <- Enum.with_index(Map.get(@grouped, cell.date, [])) do %>
            <.duty_chip
              :if={idx < CalendarHelpers.max_chips_per_day()}
              row={row}
              slug={@slug}
            />
          <% end %>
          <%= if length(Map.get(@grouped, cell.date, [])) > CalendarHelpers.max_chips_per_day() do %>
            <% extra = length(Map.get(@grouped, cell.date, [])) - CalendarHelpers.max_chips_per_day() %>
            <button
              type="button"
              id={"calendar-day-more-#{cell.date}"}
              phx-click="open_day_modal"
              phx-value-date={Date.to_iso8601(cell.date)}
              class="text-xs text-primary hover:underline px-0.5"
            >
              +{extra} more
            </button>
          <% end %>
        </div>
      </div>

      <section :if={@someday_rows != []} id="someday-strip" class="space-y-2">
        <h3 class="text-sm font-semibold text-base-content/70">Someday</h3>
        <div class="flex flex-wrap gap-1 items-center">
          <%= for {row, idx} <- Enum.with_index(@someday_rows) do %>
            <.duty_chip
              :if={idx < CalendarHelpers.max_someday_chips()}
              row={row}
              slug={@slug}
            />
          <% end %>
          <%= if length(@someday_rows) > CalendarHelpers.max_someday_chips() do %>
            <% extra = length(@someday_rows) - CalendarHelpers.max_someday_chips() %>
            <button
              type="button"
              id="someday-more"
              phx-click="open_someday_modal"
              class="text-xs text-primary hover:underline px-0.5"
            >
              +{extra} more
            </button>
          <% end %>
        </div>
      </section>

      <.day_modal
        :if={@day_modal_date}
        date={@day_modal_date}
        rows={@day_modal_rows}
        slug={@slug}
      />

      <.someday_modal
        :if={@someday_modal_open?}
        rows={@someday_rows}
        slug={@slug}
      />
    </div>
    """
  end

  attr :row, :map, required: true
  attr :slug, :string, required: true
  attr :id_prefix, :string, default: "duty-chip"

  defp duty_chip(assigns) do
    ~H"""
    <.link
      id={"#{@id_prefix}-#{@row.duty.id}"}
      navigate={~p"/entities/#{@slug}/duties/#{@row.duty.id}"}
      class={[
        "block text-xs px-1.5 py-0.5 rounded border-l-2 truncate hover:bg-base-200",
        tier_border(@row.tier)
      ]}
    >
      <span class="font-medium">{@row.duty.title}</span>
      <span class="text-base-content/50 ml-1">{@row.duty.duty_type.name}</span>
    </.link>
    """
  end

  attr :rows, :list, required: true
  attr :slug, :string, required: true

  defp someday_modal(assigns) do
    ~H"""
    <div id="someday-modal" class="modal modal-open">
      <div class="modal-box max-w-md">
        <h3 class="font-bold text-lg">Someday</h3>
        <ul class="mt-3 space-y-1">
          <li :for={row <- @rows}>
            <.duty_chip row={row} slug={@slug} id_prefix="someday-modal-duty-chip" />
          </li>
        </ul>
        <div class="modal-action">
          <button type="button" class="btn" phx-click="close_someday_modal">Close</button>
        </div>
      </div>
      <button
        class="modal-backdrop"
        type="button"
        phx-click="close_someday_modal"
        aria-label="Close"
      />
    </div>
    """
  end

  attr :date, :any, required: true
  attr :rows, :list, required: true
  attr :slug, :string, required: true

  defp day_modal(assigns) do
    ~H"""
    <div id="day-modal" class="modal modal-open">
      <div class="modal-box max-w-md">
        <h3 class="font-bold text-lg">
          {Calendar.strftime(@date, "%A, %B %-d")}
        </h3>
        <ul class="mt-3 space-y-1">
          <li :for={row <- @rows}>
            <.duty_chip row={row} slug={@slug} id_prefix="day-modal-duty-chip" />
          </li>
        </ul>
        <div class="modal-action">
          <button type="button" class="btn" phx-click="close_day_modal">Close</button>
        </div>
      </div>
      <button class="modal-backdrop" type="button" phx-click="close_day_modal" aria-label="Close" />
    </div>
    """
  end
end
