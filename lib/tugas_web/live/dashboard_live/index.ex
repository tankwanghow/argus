defmodule TugasWeb.DashboardLive.Index do
  use TugasWeb, :live_view

  alias TugasWeb.DashboardLive.CalendarHelpers, as: Calendar
  alias TugasWeb.DashboardLive.IndexHelpers, as: Dashboard

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} container_class="max-w-7xl">
      <div id="dashboard" class="tugas-page space-y-4">
        <div class="flex flex-wrap items-center gap-2">
          <div id="dashboard-scope-toggle" class="tabs tabs-box">
            <button
              id="dashboard-scope-mine"
              type="button"
              phx-click="set_scope"
              phx-value-mine="true"
              class={["tab", @mine? && "tab-active font-bold"]}
            >
              Mine
            </button>
            <button
              id="dashboard-scope-team"
              type="button"
              phx-click="set_scope"
              phx-value-mine="false"
              class={["tab", !@mine? && "tab-active font-bold"]}
            >
              Team
            </button>
          </div>

          <div class="flex items-center gap-1">
            <button
              id="dashboard-prev-month"
              type="button"
              class="btn btn-outline text-3xl font-bold"
              phx-click="prev_month"
            >
              ‹
            </button>
            <span id="dashboard-month-label" class="text-sm font-semibold min-w-32 text-center">
              {Calendar.month_label(@year, @month)}
            </span>
            <button
              id="dashboard-next-month"
              type="button"
              class="btn btn-outline text-3xl font-bold"
              phx-click="next_month"
            >
              ›
            </button>
            <button
              id="dashboard-today"
              type="button"
              class="btn btn-outline"
              phx-click="today"
            >
              Today
            </button>
          </div>
        </div>

        <div class="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_15%]">
          <div class="flex h-full min-h-0 min-w-0 flex-col">
            <.duty_calendar
              grid={@grid}
              grouped={@grouped}
              someday_rows={@someday_rows}
              slug={@current_scope.entity.slug}
              day_modal_date={@day_modal_date}
              day_modal_rows={@day_modal_rows}
              someday_modal_open?={@someday_modal_open?}
            />
          </div>

          <.dashboard_todos_panel
            todos={@todos}
            completed_todos={@completed_todos}
            slug={@current_scope.entity.slug}
            row_effects={@row_effects}
          />
        </div>
      </div>
    </Layouts.app>
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