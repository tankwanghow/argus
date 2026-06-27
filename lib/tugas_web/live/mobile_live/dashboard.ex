defmodule TugasWeb.MobileLive.Dashboard do
  use TugasWeb, :live_view

  alias TugasWeb.DashboardLive.CalendarHelpers, as: Calendar
  alias TugasWeb.DashboardLive.IndexHelpers, as: Dashboard

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} nav_context={:calendar}>
      <div class="sticky top-0 z-30 px-4 py-3 bg-base-100/95 backdrop-blur border-b border-base-200 space-y-2">
        <h1 class="flex items-center gap-2 text-lg font-semibold truncate">
          <.brand_logo class="size-9" /> Calendar -
          <span class="text-base-content/50">{@current_scope.entity.slug}</span>
        </h1>
        <div id="dashboard-scope-toggle" class="tabs tabs-box">
          <button
            id="dashboard-scope-mine"
            type="button"
            phx-click="set_scope"
            phx-value-mine="true"
            class={["tab flex-1", @mine? && "tab-active font-bold"]}
          >
            Mine
          </button>
          <button
            id="dashboard-scope-team"
            type="button"
            phx-click="set_scope"
            phx-value-mine="false"
            class={["tab flex-1", !@mine? && "tab-active font-bold"]}
          >
            Team
          </button>
        </div>
        <div class="flex items-center gap-1">
          <button
            id="dashboard-prev-month"
            type="button"
            class="btn btn-outline btn-sm font-bold"
            phx-click="prev_month"
          >
            ‹
          </button>
          <span id="dashboard-month-label" class="text-sm font-semibold flex-1 text-center">
            {Calendar.month_label(@year, @month)}
          </span>
          <button
            id="dashboard-next-month"
            type="button"
            class="btn btn-outline btn-sm font-bold"
            phx-click="next_month"
          >
            ›
          </button>
          <button
            id="dashboard-today"
            type="button"
            class="btn btn-outline btn-sm"
            phx-click="today"
          >
            Today
          </button>
        </div>
      </div>

      <div id="m-dashboard" class="px-4 py-4 space-y-4">
        <.duty_calendar
          variant={:mobile}
          grid={@grid}
          grouped={@grouped}
          someday_rows={@someday_rows}
          slug={@current_scope.entity.slug}
          day_modal_date={@day_modal_date}
          day_modal_rows={@day_modal_rows}
          someday_modal_open?={@someday_modal_open?}
        />
        <.dashboard_todos_panel
          variant={:mobile}
          todos={@todos}
          completed_todos={@completed_todos}
          slug={@current_scope.entity.slug}
          row_effects={@row_effects}
        />
      </div>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(_params, session, socket), do: Dashboard.mount_dashboard(socket, session)

  @impl true
  def handle_event("set_scope", %{"mine" => mine}, socket) do
    {:noreply, Dashboard.handle_set_scope(socket, mine)}
  end

  def handle_event("prev_month", _params, socket) do
    {:noreply, Dashboard.handle_prev_month(socket)}
  end

  def handle_event("next_month", _params, socket) do
    {:noreply, Dashboard.handle_next_month(socket)}
  end

  def handle_event("today", _params, socket) do
    {:noreply, Dashboard.handle_today(socket)}
  end

  def handle_event("open_day_modal", %{"date" => iso}, socket) do
    {:noreply, Dashboard.handle_open_day_modal(socket, iso)}
  end

  def handle_event("close_day_modal", _params, socket) do
    {:noreply, Dashboard.handle_close_day_modal(socket)}
  end

  def handle_event("open_someday_modal", _params, socket) do
    {:noreply, Dashboard.handle_open_someday_modal(socket)}
  end

  def handle_event("close_someday_modal", _params, socket) do
    {:noreply, Dashboard.handle_close_someday_modal(socket)}
  end

  def handle_event("toggle_todo_complete", %{"id" => id}, socket) do
    {:noreply, Dashboard.handle_toggle_todo_complete(socket, id)}
  end

  def handle_event("finish_row_effect", %{"id" => id}, socket) do
    {:noreply, Dashboard.handle_finish_row_effect(socket, id)}
  end

  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, Dashboard.handle_close_modal_on_escape(socket)}
  end
end
