defmodule TugasWeb.DutyLive.Index do
  use TugasWeb, :live_view

  alias Tugas.Authorization
  alias Tugas.Duties.Urgency
  alias TugasWeb.DutiesFilter
  alias TugasWeb.DutyLive.IndexHelpers, as: Index

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="dashboard" class="tugas-page">
        <div class="tugas-page-toolbar space-y-3">
          <.header>
            Duties
            <:actions>
              <.link
                :if={Authorization.can?(@current_scope, :create_duty)}
                navigate={~p"/entities/#{@current_scope.entity.slug}/duties/new"}
                class="btn btn-primary btn-sm"
              >
                + New duty
              </.link>
            </:actions>
          </.header>

          <div class="flex flex-wrap items-center gap-2">
            <div id="duty-scope-toggle" class="tabs tabs-box">
              <button
                id="scope-mine"
                type="button"
                phx-click="set_scope"
                phx-value-mine="true"
                class={["tab", @mine? && "tab-active font-bold"]}
              >
                Mine
              </button>
              <button
                id="scope-team"
                type="button"
                phx-click="set_scope"
                phx-value-mine="false"
                class={["tab", !@mine? && "tab-active font-bold"]}
              >
                Team
              </button>
            </div>
            <form id="duty-status-filter" phx-change="set_status">
              <select name="lifecycle" class="select">
                <option
                  :for={{value, label} <- Index.lifecycles()}
                  value={value}
                  selected={@lifecycle == Index.parse_lifecycle(value)}
                >
                  {label}
                </option>
              </select>
            </form>
            <form id="duty-sort-filter" phx-change="set_sort">
              <select id="duty-sort" name="sort" class="select">
                <option
                  :for={{value, label} <- Index.sorts(@lifecycle)}
                  value={value}
                  selected={@sort == Index.parse_sort(value)}
                >
                  {label}
                </option>
              </select>
            </form>
            <input
              id="duty-search"
              type="search"
              name="q"
              placeholder="Search…"
              phx-keyup="search"
              phx-debounce="150"
              value={@query}
              class="input w-full sm:w-48 sm:ml-auto"
            />
          </div>
        </div>

        <div class="tugas-page-body">
          <ul
            id="duties-list"
            class="tugas-row-list"
            phx-update="stream"
            phx-viewport-bottom={!@end? && "load_more"}
          >
            <li
              :for={{dom_id, row} <- @streams.rows}
              id={dom_id}
              data-event-count={row.event_count}
              data-event-status={row.latest_event && row.latest_event.status}
            >
              <.duty_row_link
                row={row}
                slug={@current_scope.entity.slug}
                today={@today}
                timezone={@current_scope.entity.timezone}
              />
            </li>
          </ul>
          <div
            :if={@empty?}
            id="duties-empty"
            class="py-8 text-center text-base-content/60"
          >
            {Index.empty_message(@mine?, @lifecycle)}
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :row, :map, required: true
  attr :slug, :string, required: true
  attr :today, :any, required: true
  attr :timezone, :string, default: nil

  defp duty_row_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/entities/#{@slug}/duties/#{@row.duty.id}"}
      class={[
        "tugas-compact-row",
        if(@row.cycle_status == :live and @row.duty.due_by,
          do: tier_border(@row.tier),
          else: "border-transparent"
        )
      ]}
    >
      <div class="flex justify-between items-center gap-x-2 gap-y-0.5">
        <div class="font-medium">{@row.duty.title}</div>
        <.cycle_badge
          cycle_status={@row.cycle_status}
          tier={@row.tier}
          duty={@row.duty}
          today={@today}
          timezone={@timezone}
          in_error={!is_nil(@row.duty.completed_in_error_at)}
        />
      </div>
      <div class="flex items-center text-sm gap-1">
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
      />
    </.link>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    scope = socket.assigns.current_scope
    today = Urgency.today_for(scope.entity.timezone)

    {:ok,
     socket
     |> assign(:today, today)
     |> DutiesFilter.assign_filters(session)
     |> load_first_page()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if DutiesFilter.prefilter_params?(params) do
      {:noreply,
       socket
       |> DutiesFilter.apply_params(params)
       |> load_first_page()
       |> DutiesFilter.persist()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_scope", %{"mine" => mine}, socket) do
    {:noreply,
     socket
     |> assign(:mine?, mine == "true")
     |> load_first_page()
     |> DutiesFilter.persist()}
  end

  def handle_event("set_status", %{"lifecycle" => lifecycle}, socket) do
    {:noreply,
     socket
     |> assign(:lifecycle, Index.parse_lifecycle(lifecycle))
     |> load_first_page()
     |> DutiesFilter.persist()}
  end

  def handle_event("set_sort", %{"sort" => sort}, socket) do
    {:noreply,
     socket
     |> assign(:sort, Index.parse_sort(sort))
     |> load_first_page()
     |> DutiesFilter.persist()}
  end

  def handle_event("search", %{"value" => query}, socket) do
    {:noreply,
     socket
     |> assign(:query, query)
     |> load_first_page()
     |> DutiesFilter.persist()}
  end

  def handle_event("load_more", _params, socket) do
    %{
      current_scope: scope,
      today: today,
      mine?: mine?,
      lifecycle: lifecycle,
      query: query,
      sort: sort,
      cursor: cursor
    } = socket.assigns

    %{rows: rows, cursor: cursor, end?: end?} =
      Index.load_page(scope, today, mine?, lifecycle, query, sort, cursor)

    {:noreply,
     socket
     |> stream(:rows, rows, dom_id: &row_dom_id/1, at: -1)
     |> assign(cursor: cursor, end?: end?)}
  end

  def handle_event("close_modal_on_escape", _params, socket), do: {:noreply, socket}

  defp load_first_page(socket) do
    %{
      current_scope: scope,
      today: today,
      mine?: mine?,
      lifecycle: lifecycle,
      query: query,
      sort: sort
    } = socket.assigns

    %{rows: rows, cursor: cursor, end?: end?} =
      Index.load_page(scope, today, mine?, lifecycle, query, sort, nil)

    socket
    |> stream(:rows, rows, dom_id: &row_dom_id/1, reset: true)
    |> assign(cursor: cursor, end?: end?, empty?: rows == [])
  end

  defp row_dom_id(row), do: "duty-row-#{row.duty.id}"

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
