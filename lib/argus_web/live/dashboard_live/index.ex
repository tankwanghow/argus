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
          <:actions>
            <span
              :if={@grouped.overdue != []}
              class="badge badge-error gap-1"
              data-overdue-count={length(@grouped.overdue)}
            >
              <.icon name="hero-exclamation-triangle-mini" class="size-4" />
              {length(@grouped.overdue)} overdue
            </span>
          </:actions>
        </.header>

        <div class="tabs tabs-box mt-6 w-fit">
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

        <div class="mt-6 space-y-6">
          <.tier
            :for={tier <- tiers()}
            :if={tier_rows(@grouped, tier.key) != []}
            tier={tier}
            rows={tier_rows(@grouped, tier.key)}
            today={@today}
            slug={@current_scope.entity.slug}
          />

          <div
            :if={@rows == []}
            id="dashboard-empty"
            class="rounded-box border border-dashed border-base-300 py-12 text-center text-base-content/60"
          >
            <.icon name="hero-check-circle" class="size-8 mx-auto mb-2 opacity-50" />
            <p>Nothing on your plate. No live obligations.</p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :tier, :map, required: true
  attr :rows, :list, required: true
  attr :today, Date, required: true
  attr :slug, :string, required: true

  defp tier(assigns) do
    ~H"""
    <section data-tier={@tier.key}>
      <h2 class={[
        "flex items-center gap-2 text-sm font-semibold uppercase tracking-wide",
        @tier.color
      ]}>
        <span class={["inline-block size-2 rounded-full", @tier.dot]} />
        {@tier.label}
        <span class="text-base-content/50 font-normal">({length(@rows)})</span>
      </h2>

      <ul class="mt-3 divide-y divide-base-300 rounded-box border border-base-300">
        <li :for={row <- @rows} id={"obligation-row-#{row.obligation.id}"}>
          <.link
            navigate={~p"/entities/#{@slug}/obligations/#{row.obligation.id}"}
            class={["flex items-center gap-3 p-3 hover:bg-base-200 border-l-4", @tier.accent]}
          >
            <div class="flex-1 min-w-0">
              <div class="font-medium truncate">{row.obligation.title}</div>
              <div class="text-sm text-base-content/60 truncate">
                {row.obligation.obligation_type.name} · {row.obligation.primary_assignee.email}
              </div>
            </div>
            <div class="text-right shrink-0">
              <div class="text-sm">{format_date(row.obligation.due_by)}</div>
              <div class={["text-xs", @tier.color]}>{due_label(row.obligation.due_by, @today)}</div>
            </div>
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  defp tiers do
    [
      %{
        key: :overdue,
        label: "Overdue",
        color: "text-error",
        dot: "bg-error",
        accent: "border-error"
      },
      %{
        key: :due_soon,
        label: "Due soon",
        color: "text-warning",
        dot: "bg-warning",
        accent: "border-warning"
      },
      %{
        key: :ok,
        label: "On track",
        color: "text-base-content/60",
        dot: "bg-base-300",
        accent: "border-transparent"
      }
    ]
  end

  defp tier_rows(grouped, key), do: Map.get(grouped, key, [])

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

    grouped =
      Map.merge(
        %{overdue: [], due_soon: [], ok: []},
        Enum.group_by(rows, & &1.urgency)
      )

    assign(socket, rows: rows, grouped: grouped)
  end

  defp sort_by_urgency(rows) do
    Enum.sort_by(rows, fn %{obligation: o, urgency: urgency} ->
      {@urgency_rank[urgency], o.due_by}
    end)
  end
end
