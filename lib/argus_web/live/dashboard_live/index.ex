defmodule ArgusWeb.DashboardLive.Index do
  use ArgusWeb, :live_view

  alias Argus.Authorization
  alias Argus.Obligations.Urgency
  alias ArgusWeb.ObligationLive.IndexHelpers, as: Index

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="dashboard" class="argus-page">
        <div class="argus-page-toolbar space-y-3">
          <.header>
            Dashboard
            <:actions>
              <.link
                :if={Authorization.can?(@current_scope, :create_obligation)}
                navigate={~p"/entities/#{@current_scope.entity.slug}/obligations/new"}
                class="btn btn-primary btn-sm"
              >
                + New duty
              </.link>
            </:actions>
          </.header>

          <div class="flex flex-wrap items-center gap-2">
            <div id="obligation-scope-toggle" class="tabs tabs-box">
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
            <form id="obligation-status-filter" phx-change="set_status">
              <select name="lifecycle" class="select select-sm">
                <option
                  :for={{value, label} <- Index.lifecycles()}
                  value={value}
                  selected={@lifecycle == Index.parse_lifecycle(value)}
                >
                  {label}
                </option>
              </select>
            </form>
            <input
              id="obligation-search"
              type="search"
              name="q"
              placeholder="Search…"
              phx-keyup="search"
              phx-debounce="150"
              value={@query}
              class="input input-sm w-full sm:w-48 sm:ml-auto"
            />
          </div>
        </div>

        <div class="argus-page-body">
          <ul id="obligations-list" class="argus-row-list">
            <li
              :for={row <- @rows}
              id={"obligation-row-#{row.obligation.id}"}
              data-event-count={row.event_count}
              data-event-status={row.latest_event && row.latest_event.status}
            >
              <.obligation_row_link row={row} slug={@current_scope.entity.slug} today={@today} />
            </li>
            <li
              :if={@rows == []}
              id="obligations-empty"
              class="py-8 text-center text-base-content/60"
            >
              {Index.empty_message(@mine?, @lifecycle)}
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :row, :map, required: true
  attr :slug, :string, required: true
  attr :today, :any, required: true

  defp obligation_row_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/entities/#{@slug}/obligations/#{@row.obligation.id}"}
      class={[
        "argus-compact-row",
        if(@row.cycle_status == :live, do: tier_border(@row.tier), else: "border-transparent")
      ]}
    >
      <div class="flex flex-wrap items-center gap-x-2 gap-y-0.5">
        <span class="font-medium">{@row.obligation.title}</span>
        <span :if={@row.obligation.completed_in_error_at} class="badge badge-xs badge-error">
          in error
        </span>
        <.urgency_badge
          :if={@row.cycle_status == :live}
          tier={@row.tier}
          due_by={@row.obligation.due_by}
          today={@today}
        />
        <.obligation_status_badge
          :if={@row.cycle_status != :live}
          cycle_status={@row.cycle_status}
          in_error={!is_nil(@row.obligation.completed_in_error_at)}
          detail={completion_detail(@row)}
        />
      </div>
      <div class="flex text-sm gap-1">
        <div class="text-info">{@row.obligation.obligation_type.name}</div>
        <div>·</div>
        <div class="text-base-content/60">
          due {format_date(@row.obligation.due_by)}
        </div>
        <div>·</div>
        {assignee_label(@row.obligation.primary_assignee)}
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
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    today = Urgency.today_for(scope.entity.timezone)

    {:ok,
     socket
     |> assign(:today, today)
     |> assign(:mine?, Index.default_mine?(scope))
     |> assign(:lifecycle, :live)
     |> assign(:query, "")
     |> load_rows()}
  end

  @impl true
  def handle_event("set_scope", %{"mine" => mine}, socket) do
    {:noreply, socket |> assign(:mine?, mine == "true") |> load_rows()}
  end

  def handle_event("set_status", %{"lifecycle" => lifecycle}, socket) do
    {:noreply, socket |> assign(:lifecycle, Index.parse_lifecycle(lifecycle)) |> load_rows()}
  end

  def handle_event("search", %{"value" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> load_rows()}
  end

  def handle_event("close_modal_on_escape", _params, socket), do: {:noreply, socket}

  defp load_rows(socket) do
    %{current_scope: scope, today: today, mine?: mine?, lifecycle: lifecycle, query: query} =
      socket.assigns

    assign(socket, :rows, Index.load_rows(scope, today, mine?, lifecycle, query))
  end

  defp assignee_label(assigns) when assigns == nil do
    ~H"""
    <div class="text-error">Unassigned</div>
    """
  end

  defp assignee_label(assigns) do
    ~H"""
    <div>{assigns.email}</div>
    """
  end

  defp completion_detail(%{cycle_status: :completed, obligation: o}),
    do: format_completed_at(o.completed_at)

  defp completion_detail(_), do: nil

  defp format_completed_at(nil), do: "—"

  defp format_completed_at(%DateTime{} = dt) do
    dt
    |> DateTime.to_date()
    |> format_date()
  end
end
