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
            <:subtitle>{@current_scope.entity.name}</:subtitle>
            <:actions>
              <.link
                :if={Authorization.can?(@current_scope, :create_obligation)}
                navigate={~p"/entities/#{@current_scope.entity.slug}/obligations/new"}
                class="btn btn-primary btn-sm"
              >
                New obligation
              </.link>
            </:actions>
          </.header>

          <div class="flex flex-col gap-2 sm:flex-row sm:items-center">
            <div id="obligation-status-filters" class="tabs tabs-box tabs-wrap flex-1 min-w-0">
              <.link
                :for={status <- Index.statuses()}
                id={"filter-#{status}"}
                phx-click="filter_status"
                phx-value-status={status}
                class={["tab", @status == Index.parse_status(status) && "tab-active font-bold"]}
              >
                {Index.status_label(Index.parse_status(status))}
              </.link>
            </div>
            <input
              id="obligation-search"
              type="search"
              name="q"
              placeholder="Search…"
              phx-keyup="search"
              phx-debounce="150"
              value={@query}
              class="input input-sm w-full sm:w-48 shrink-0"
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
              {Index.empty_message(@status)}
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
      <div class="text-sm text-base-content/60 mt-0.5">
        due {format_date(@row.obligation.due_by)}
      </div>
      <div class="text-sm text-base-content/60 mt-0.5">{obligation_subtitle(@row.obligation)}</div>
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
     |> assign(:status, Index.default_status(scope))
     |> assign(:query, "")
     |> load_rows()}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:status, Index.parse_status(status)) |> load_rows()}
  end

  def handle_event("search", %{"value" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> load_rows()}
  end

  def handle_event("close_modal_on_escape", _params, socket), do: {:noreply, socket}

  defp load_rows(socket) do
    %{current_scope: scope, today: today, status: status, query: query} = socket.assigns
    assign(socket, :rows, Index.load_rows(scope, today, status, query))
  end

  defp obligation_subtitle(obligation) do
    "#{obligation.obligation_type.name} · #{assignee_label(obligation)}"
  end

  defp assignee_label(%{primary_assignee: nil}), do: "Unassigned"
  defp assignee_label(%{primary_assignee: assignee}), do: assignee.email

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
