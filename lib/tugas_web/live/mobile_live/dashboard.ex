defmodule TugasWeb.MobileLive.Dashboard do
  use TugasWeb, :live_view

  alias Tugas.Authorization
  alias TugasWeb.DashboardLive.CalendarHelpers, as: Calendar
  alias TugasWeb.DashboardLive.IndexHelpers, as: Dashboard
  alias TugasWeb.DutyLive.FormComponent

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope} nav_context={:calendar}>
      <div class="flex h-[calc(100dvh-3.5rem-env(safe-area-inset-bottom,0px))] min-h-0 flex-col">
        <div class="sticky top-0 z-30 shrink-0 px-4 pt-3 bg-base-100/95 backdrop-blur space-y-1">
          <div id="dashboard-toolbar" class="flex flex-wrap items-center justify-center gap-1">
            <button
              id="dashboard-prev-month"
              type="button"
              class="border border-base-300 rounded-lg px-3 py-1 font-bold"
              phx-click="prev_month"
            >
              ‹
            </button>
            <span id="dashboard-month-label" class="font-semibold min-w-20 text-center">
              {Calendar.month_label(@year, @month)}
            </span>
            <button
              id="dashboard-next-month"
              type="button"
              class="border border-base-300 rounded-lg px-3 py-1 font-bold"
              phx-click="next_month"
            >
              ›
            </button>
            <button
              id="dashboard-today"
              type="button"
              class="border border-base-300 rounded-lg px-2 py-1"
              phx-click="today"
            >
              Today
            </button>
            <button
              :if={Authorization.can?(@current_scope, :create_duty)}
              id="dashboard-new-duty"
              type="button"
              class="btn btn-primary btn-sm"
              phx-click="open_create_duty"
            >
              + Duty
            </button>
            <button
              id="dashboard-new-todo"
              type="button"
              class="btn btn-secondary btn-sm"
              phx-click="open_new_todo"
            >
              + Todo
            </button>
          </div>
        </div>

        <div
          id="m-dashboard"
          phx-hook="DashboardSwipe"
          data-dashboard-calendar="2"
          class="flex min-h-0 flex-1 flex-col px-1 py-1 gap-1"
        >
          <div id="m-dashboard-swipe-hint" class="tabs tabs-box w-full shrink-0">
            <button
              type="button"
              id="m-dashboard-go-someday"
              data-dashboard-go="0"
              class="tab flex-1 min-h-8 text-sm"
            >
              someday
            </button>
            <button
              type="button"
              id="m-dashboard-go-urgent"
              data-dashboard-go="1"
              class="tab flex-1 min-h-8 text-sm"
            >
              urgent
            </button>
            <button
              type="button"
              id="m-dashboard-go-calendar"
              data-dashboard-go="2"
              class="tab flex-1 min-h-8 text-sm tab-active font-bold"
            >
              calendar
            </button>
            <button
              type="button"
              id="m-dashboard-go-todos"
              data-dashboard-go="3"
              class="tab flex-1 min-h-8 text-sm"
            >
              todo
            </button>
          </div>

          <div id="m-dashboard-panels" class="relative flex min-h-0 flex-1 flex-col">
            <div
              data-dashboard-panel="0"
              class="hidden min-h-0 flex-1 overflow-y-auto pr-2"
            >
              <.mobile_someday_panel
                rows={@someday_rows}
                slug={@current_scope.entity.slug}
                variant={:mobile}
              />
            </div>

            <div
              data-dashboard-panel="1"
              class="hidden min-h-0 flex-1 overflow-y-auto pr-2"
            >
              <.urgent_panel
                rows={@urgent_rows}
                slug={@current_scope.entity.slug}
                variant={:mobile}
              />
            </div>

            <div
              data-dashboard-panel="2"
              class="flex min-h-0 flex-1 flex-col overflow-hidden px-1"
            >
              <.duty_calendar
                variant={:mobile}
                hide_someday_strip?={true}
                grid={@grid}
                grouped={@grouped}
                someday_rows={@someday_rows}
                slug={@current_scope.entity.slug}
                day_modal_date={@day_modal_date}
                day_modal_rows={@day_modal_rows}
                day_modal_holidays={@day_modal_holidays}
              />
            </div>

            <div
              data-dashboard-panel="3"
              class="hidden min-h-0 flex-1 overflow-y-auto pl-2"
            >
              <.dashboard_todos_panel
                variant={:mobile}
                todos={@todos}
                completed_todos={@completed_todos}
                slug={@current_scope.entity.slug}
                row_effects={@row_effects}
              />
            </div>
          </div>
        </div>

        <.live_component
          :if={@create_duty_open?}
          module={FormComponent}
          id="duty-form-modal"
          current_scope={@current_scope}
          from_todo_id={@create_duty_from_todo_id}
        />

        <.new_todo_modal :if={@new_todo_open?} />
      </div>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(_params, session, socket), do: Dashboard.mount_dashboard(socket, session)

  @impl true
  def handle_params(params, _uri, socket) do
    if socket.assigns.live_action == :new and
         Authorization.can?(socket.assigns.current_scope, :create_duty) do
      {:noreply, Dashboard.handle_open_create_duty(socket, params)}
    else
      {:noreply, socket}
    end
  end

  @impl true
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

  def handle_event("toggle_todo_complete", %{"id" => id}, socket) do
    {:noreply, Dashboard.handle_toggle_todo_complete(socket, id)}
  end

  def handle_event("finish_row_effect", %{"id" => id}, socket) do
    {:noreply, Dashboard.handle_finish_row_effect(socket, id)}
  end

  def handle_event("open_create_duty", _params, socket) do
    {:noreply, Dashboard.handle_open_create_duty(socket)}
  end

  def handle_event("close_create_duty", _params, socket) do
    {:noreply, Dashboard.handle_close_create_duty(socket)}
  end

  def handle_event("open_new_todo", _params, socket) do
    {:noreply, Dashboard.handle_open_new_todo(socket)}
  end

  def handle_event("close_new_todo", _params, socket) do
    {:noreply, Dashboard.handle_close_new_todo(socket)}
  end

  def handle_event("create_todo", %{"title" => title}, socket) do
    {:noreply, Dashboard.handle_create_todo(socket, title)}
  end

  def handle_event("close_modal_on_escape", _params, socket) do
    {:noreply, Dashboard.handle_close_modal_on_escape(socket)}
  end

  @impl true
  def handle_info({:duty_created, duty, from_todo_id}, socket) do
    {:noreply, Dashboard.handle_duty_created(socket, duty, from_todo_id)}
  end
end
