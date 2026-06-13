defmodule ArgusWeb.ObligationLive.Index do
  use ArgusWeb, :live_view

  alias Argus.Obligations
  alias Argus.Obligations.Urgency

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="obligations-index">
        <.header>
          Obligations
          <:actions>
            <.link
              :if={Argus.Authorization.can?(@current_scope, :create_obligation)}
              navigate={~p"/entities/#{@current_scope.entity.slug}/obligations/new"}
              class="btn btn-primary btn-sm"
            >
              New obligation
            </.link>
          </:actions>
        </.header>

        <ul id="obligations-list" class="mt-6 divide-y divide-base-300">
          <li :for={row <- @rows} id={"obligation-#{row.obligation.id}"} class="py-3">
            <.link
              navigate={~p"/entities/#{@current_scope.entity.slug}/obligations/#{row.obligation.id}"}
              class="flex items-center justify-between gap-3 hover:opacity-80"
            >
              <div class="min-w-0">
                <div class="font-medium truncate">{row.obligation.title}</div>
                <div class="text-sm text-base-content/60 truncate">
                  {row.obligation.obligation_type.name} · due {format_date(row.obligation.due_by)} · {due_label(
                    row.obligation.due_by,
                    @today
                  )}
                </div>
              </div>
              <.urgency_badge urgency={row.urgency} />
            </.link>
          </li>
          <li :if={@rows == []} class="py-8 text-center text-base-content/60">
            No live obligations.
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    today = Urgency.today_for(scope.entity.timezone)

    rows =
      Obligations.list_team_overview(scope)
      |> Enum.map(fn obligation ->
        %{
          obligation: obligation,
          urgency: Urgency.classify(obligation.obligation_type, obligation.due_by, today)
        }
      end)

    {:ok, assign(socket, rows: rows, today: today)}
  end
end
