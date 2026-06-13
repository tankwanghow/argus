defmodule ArgusWeb.DashboardLive.Index do
  use ArgusWeb, :live_view

  alias Argus.Obligations
  alias Argus.Obligations.Urgency

  @urgency_rank %{overdue: 0, due_soon: 1, ok: 2}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="dashboard">
        <.header>
          Dashboard
          <:subtitle>{@current_scope.entity.name}</:subtitle>
        </.header>

        <div class="tabs tabs-boxed mt-6 w-fit">
          <button
            id="tab-my-work"
            type="button"
            phx-click="switch_tab"
            phx-value-tab="my_work"
            class={["tab", @tab == :my_work && "tab-active"]}
          >
            My work
          </button>
          <button
            id="tab-team-overview"
            type="button"
            phx-click="switch_tab"
            phx-value-tab="team"
            class={["tab", @tab == :team && "tab-active"]}
          >
            Team overview
          </button>
        </div>

        <div class="mt-6 overflow-x-auto">
          <table id="obligations-table" class="table table-zebra">
            <thead>
              <tr>
                <th>Title</th>
                <th>Type</th>
                <th>Assignee</th>
                <th>Due</th>
                <th>Urgency</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @rows} id={"obligation-row-#{row.obligation.id}"}>
                <td>{row.obligation.title}</td>
                <td>{row.obligation.obligation_type.name}</td>
                <td>{row.obligation.primary_assignee.email}</td>
                <td>{row.obligation.due_by}</td>
                <td><.urgency_badge urgency={row.urgency} /></td>
              </tr>
              <tr :if={@rows == []}>
                <td colspan="5" class="text-center text-base-content/60 py-8">
                  No live obligations.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    today = Urgency.today_for(scope.entity.timezone)
    tab = default_tab(scope.role)

    {:ok,
     socket
     |> assign(:today, today)
     |> assign(:tab, tab)
     |> load_rows(scope, tab, today)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = if tab == "team", do: :team, else: :my_work

    {:noreply,
     socket
     |> assign(:tab, tab)
     |> load_rows(socket.assigns.current_scope, tab, socket.assigns.today)}
  end

  defp default_tab(:member), do: :my_work
  defp default_tab(_), do: :team

  defp load_rows(socket, scope, tab, today) do
    obligations =
      case tab do
        :my_work -> Obligations.list_my_work(scope)
        :team -> Obligations.list_team_overview(scope)
      end

    rows =
      obligations
      |> Enum.map(fn obligation ->
        %{
          obligation: obligation,
          urgency: Urgency.classify(obligation.obligation_type, obligation.due_by, today)
        }
      end)
      |> sort_by_urgency()

    assign(socket, :rows, rows)
  end

  defp sort_by_urgency(rows) do
    Enum.sort_by(rows, fn %{obligation: o, urgency: urgency} ->
      {@urgency_rank[urgency], o.due_by}
    end)
  end
end
