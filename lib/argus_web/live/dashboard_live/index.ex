defmodule ArgusWeb.DashboardLive.Index do
  use ArgusWeb, :live_view

  alias Argus.Obligations
  alias Argus.Obligations.Urgency

  @urgency_rank %{overdue: 0, due_soon: 1, ok: 2}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="dashboard" class="argus-page">
        <div class="argus-page-toolbar space-y-3">
          <.header>
            Dashboard
            <:subtitle>{@current_scope.entity.name}</:subtitle>
          </.header>

          <div class="flex flex-wrap items-center gap-3">
            <div class="tabs tabs-box w-fit bg-base-200/80">
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

            <.team_summary :if={@tab == :team} chips={@summary_chips} />
          </div>
        </div>

        <div class="argus-page-body space-y-3">
          <%= if @tab == :team do %>
            <.tier
              :for={tier <- urgency_tiers()}
              :if={tier_rows(@grouped, tier.key) != []}
              tier={tier}
              rows={tier_rows(@grouped, tier.key)}
              today={@today}
              slug={@current_scope.entity.slug}
              show_assignee
            />

            <.unassigned_section
              :if={@unassigned_rows != []}
              rows={@unassigned_rows}
              today={@today}
              slug={@current_scope.entity.slug}
            />

            <.collapsible_tier
              :if={tier_rows(@grouped, :ok) != []}
              id="tier-on-track"
              tier={on_track_tier()}
              rows={tier_rows(@grouped, :ok)}
              today={@today}
              slug={@current_scope.entity.slug}
              show_assignee
              collapsed={@on_track_collapsed}
            />

            <.recently_completed
              :if={@recently_completed_rows != []}
              rows={@recently_completed_rows}
              slug={@current_scope.entity.slug}
              collapsed={@recent_collapsed}
            />
          <% else %>
            <.tier
              :for={tier <- urgency_tiers()}
              :if={tier_rows(@grouped, tier.key) != []}
              tier={tier}
              rows={tier_rows(@grouped, tier.key)}
              today={@today}
              slug={@current_scope.entity.slug}
            />
          <% end %>

          <div
            :if={empty_dashboard?(@tab, @grouped, @unassigned_rows, @recently_completed_rows)}
            id="dashboard-empty"
            class="argus-section py-12 text-center text-base-content/60 border-dashed"
          >
            <.icon name="hero-check-circle" class="size-8 mx-auto mb-2 opacity-50" />
            <p>Nothing on your plate. No live obligations.</p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :chips, :list, required: true

  defp team_summary(assigns) do
    ~H"""
    <div id="team-summary" class="flex flex-wrap gap-2">
      <span
        :for={chip <- @chips}
        :if={chip.count > 0}
        id={"summary-#{chip.key}"}
        class={["badge badge-sm gap-1", chip.badge]}
        data-count={chip.count}
      >
        <.icon :if={chip.icon} name={chip.icon} class="size-3.5" />
        {chip.count} {chip.label}
      </span>
    </div>
    """
  end

  attr :tier, :map, required: true
  attr :rows, :list, required: true
  attr :today, Date, required: true
  attr :slug, :string, required: true
  attr :show_assignee, :boolean, default: false

  defp tier(assigns) do
    ~H"""
    <section data-tier={@tier.key} class="argus-section">
      <div class={["argus-section-head", @tier.color]}>
        <span class={["inline-block size-2 rounded-full shrink-0", @tier.dot]} />
        {@tier.label}
        <span class="text-base-content/50 font-normal">({length(@rows)})</span>
      </div>

      <.obligation_rows
        rows={@rows}
        tier={@tier}
        today={@today}
        slug={@slug}
        show_assignee={@show_assignee}
      />
    </section>
    """
  end

  attr :id, :string, required: true
  attr :tier, :map, required: true
  attr :rows, :list, required: true
  attr :today, Date, required: true
  attr :slug, :string, required: true
  attr :show_assignee, :boolean, default: false
  attr :collapsed, :boolean, default: true

  defp collapsible_tier(assigns) do
    ~H"""
    <section data-tier={@tier.key} id={@id} class="argus-section">
      <div class="argus-section-head">
        <button
          type="button"
          phx-click="toggle_section"
          phx-value-section="on_track"
          class="flex items-center gap-2 text-left"
        >
          <.icon
            name={if @collapsed, do: "hero-chevron-right", else: "hero-chevron-down"}
            class="size-4 text-base-content/50 shrink-0"
          />
          <span class={["inline-block size-2 rounded-full shrink-0", @tier.dot]} />
          <span class={@tier.color}>{@tier.label}</span>
          <span class="text-base-content/50 font-normal">({length(@rows)})</span>
        </button>
      </div>

      <.obligation_rows
        :if={not @collapsed}
        rows={@rows}
        tier={@tier}
        today={@today}
        slug={@slug}
        show_assignee={@show_assignee}
      />
    </section>
    """
  end

  attr :rows, :list, required: true
  attr :today, Date, required: true
  attr :slug, :string, required: true

  defp unassigned_section(assigns) do
    ~H"""
    <section id="tier-unassigned" data-tier="unassigned" class="argus-section">
      <div class="argus-section-head text-secondary">
        <span class="inline-block size-2 rounded-full bg-secondary shrink-0" /> Unassigned
        <span class="text-base-content/50 font-normal">({length(@rows)})</span>
      </div>

      <ul class="argus-row-list">
        <li
          :for={row <- @rows}
          id={"unassigned-row-#{row.obligation.id}"}
          data-event-count={row.event_count}
          data-event-status={row.latest_event && row.latest_event.status}
        >
          <.obligation_row_link
            row={row}
            slug={@slug}
            today={@today}
            accent="border-secondary"
            tier_color={urgency_text_class(row.urgency)}
            subtitle={"#{row.obligation.obligation_type.name} · Unassigned"}
          />
          <div class="px-3 pb-3 -mt-1">
            <.link
              navigate={~p"/entities/#{@slug}/obligations/#{row.obligation.id}"}
              class="btn btn-ghost btn-xs text-secondary"
            >
              <.icon name="hero-user-plus" class="size-3.5" /> Assign someone
            </.link>
          </div>
        </li>
      </ul>
    </section>
    """
  end

  attr :rows, :list, required: true
  attr :slug, :string, required: true
  attr :collapsed, :boolean, default: false

  defp recently_completed(assigns) do
    ~H"""
    <section id="tier-recently-completed" data-tier="recently_completed" class="argus-section">
      <div class="argus-section-head text-base-content/70">
        <button
          type="button"
          phx-click="toggle_section"
          phx-value-section="recent"
          class="flex items-center gap-2 text-left"
        >
          <.icon
            name={if @collapsed, do: "hero-chevron-right", else: "hero-chevron-down"}
            class="size-4 text-base-content/50 shrink-0"
          />
          <span class="inline-block size-2 rounded-full bg-success/60 shrink-0" /> Recently completed
          <span class="text-base-content/50 font-normal">({length(@rows)})</span>
        </button>
      </div>

      <ul :if={not @collapsed} class="argus-row-list">
        <li :for={row <- @rows} id={"completed-row-#{row.obligation.id}"}>
          <.obligation_row_link
            row={row}
            slug={@slug}
            today={nil}
            accent="border-transparent"
            tier_color="text-base-content/60"
            subtitle={"#{row.obligation.obligation_type.name} · #{assignee_label(row.obligation)}"}
            due_label={format_completed_at(row.obligation.completed_at)}
          />
        </li>
      </ul>
    </section>
    """
  end

  attr :rows, :list, required: true
  attr :tier, :map, required: true
  attr :today, Date, required: true
  attr :slug, :string, required: true
  attr :show_assignee, :boolean, default: false

  defp obligation_rows(assigns) do
    ~H"""
    <ul class="argus-row-list">
      <li
        :for={row <- @rows}
        id={"obligation-row-#{row.obligation.id}"}
        data-event-count={row.event_count}
        data-event-status={row.latest_event && row.latest_event.status}
      >
        <.obligation_row_link
          row={row}
          slug={@slug}
          today={@today}
          accent={@tier.accent}
          tier_color={@tier.color}
          subtitle={obligation_subtitle(row, @show_assignee)}
        />
      </li>
    </ul>
    """
  end

  attr :row, :map, required: true
  attr :slug, :string, required: true
  attr :today, :any, default: nil
  attr :accent, :string, required: true
  attr :tier_color, :string, required: true
  attr :subtitle, :string, required: true
  attr :due_label, :string, default: nil

  defp obligation_row_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/entities/#{@slug}/obligations/#{@row.obligation.id}"}
      class={["argus-compact-row", @accent]}
    >
      <div class="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
        <span class="font-medium">{@row.obligation.title}</span>
        <span class="text-sm text-base-content/60">·</span>
        <span class="text-sm">{format_date(@row.obligation.due_by)}</span>
        <span :if={@due_label} class={["text-xs", @tier_color]}>{@due_label}</span>
        <span
          :if={!@due_label && @today}
          class={["text-xs", @tier_color]}
        >
          {due_label(@row.obligation.due_by, @today)}
        </span>
      </div>
      <div class="text-sm text-base-content/60 mt-0.5">{@subtitle}</div>
      <.event_meta
        :if={@row.latest_event}
        event={@row.latest_event}
        event_count={@row.event_count}
      />
    </.link>
    """
  end

  attr :event, :map, required: true
  attr :event_count, :integer, required: true

  defp event_meta(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs text-base-content/60 mt-1">
      <span class={["badge badge-xs", status_badge_class(@event.status)]}>
        {humanize_status(@event.status)}
      </span>
      <span>{event_count_label(@event_count)}</span>
      <span :if={@event.status_by}>by {@event.status_by.email}</span>
      <span :if={@event.note} class="truncate max-w-[16rem] italic text-base-content/50">
        “{truncate_note(@event.note)}”
      </span>
    </div>
    """
  end

  defp obligation_subtitle(row, show_assignee) do
    type = row.obligation.obligation_type.name

    if show_assignee do
      "#{type} · #{assignee_label(row.obligation)}"
    else
      type
    end
  end

  defp urgency_tiers do
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
      }
    ]
  end

  defp on_track_tier do
    %{
      key: :ok,
      label: "On track",
      color: "text-base-content/60",
      dot: "bg-base-300",
      accent: "border-transparent"
    }
  end

  defp tier_rows(grouped, key), do: Map.get(grouped, key, [])

  defp urgency_text_class(:overdue), do: "text-error"
  defp urgency_text_class(:due_soon), do: "text-warning"
  defp urgency_text_class(_), do: "text-base-content/60"

  defp assignee_label(%{primary_assignee: nil}), do: "Unassigned"
  defp assignee_label(%{primary_assignee: assignee}), do: assignee.email

  defp empty_dashboard?(:my_work, grouped, _, _) do
    Enum.all?([:overdue, :due_soon, :ok], &(tier_rows(grouped, &1) == []))
  end

  defp empty_dashboard?(:team, grouped, unassigned, recently_completed_rows) do
    Enum.all?([:overdue, :due_soon, :ok], &(tier_rows(grouped, &1) == [])) and
      unassigned == [] and recently_completed_rows == []
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
     |> assign(:on_track_collapsed, true)
     |> assign(:recent_collapsed, false)
     |> load_dashboard(scope, tab, today)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = if tab == "team", do: :team, else: :my_work

    {:noreply,
     socket
     |> assign(:tab, tab)
     |> load_dashboard(socket.assigns.current_scope, tab, socket.assigns.today)}
  end

  def handle_event("toggle_section", %{"section" => "on_track"}, socket) do
    {:noreply, assign(socket, :on_track_collapsed, not socket.assigns.on_track_collapsed)}
  end

  def handle_event("toggle_section", %{"section" => "recent"}, socket) do
    {:noreply, assign(socket, :recent_collapsed, not socket.assigns.recent_collapsed)}
  end

  defp default_tab(:member), do: :my_work
  defp default_tab(_), do: :team

  defp load_dashboard(socket, scope, tab, today) do
    obligations =
      case tab do
        :my_work -> Obligations.list_my_work(scope)
        :team -> Obligations.list_team_overview(scope)
      end

    rows = build_rows(obligations, today)

    grouped =
      Map.merge(
        %{overdue: [], due_soon: [], ok: []},
        Enum.group_by(rows, & &1.urgency)
      )

    socket =
      socket
      |> assign(:rows, rows)
      |> assign(:grouped, grouped)

    if tab == :team do
      unassigned_rows =
        scope
        |> Obligations.list_unassigned()
        |> build_rows(today)

      recently_completed_rows =
        scope
        |> Obligations.list_recently_completed()
        |> build_completed_rows()

      socket
      |> assign(:unassigned_rows, unassigned_rows)
      |> assign(:recently_completed_rows, recently_completed_rows)
      |> assign(:summary_chips, summary_chips(grouped, unassigned_rows))
    else
      socket
      |> assign(:unassigned_rows, [])
      |> assign(:recently_completed_rows, [])
      |> assign(:summary_chips, [])
    end
  end

  defp build_rows(obligations, today) do
    summaries = Obligations.event_summaries_for(obligations)

    obligations
    |> Enum.map(fn obligation ->
      %{event_count: event_count, latest_event: latest_event} =
        Map.fetch!(summaries, obligation.id)

      %{
        obligation: obligation,
        urgency: Urgency.classify(obligation.obligation_type, obligation.due_by, today),
        event_count: event_count,
        latest_event: latest_event
      }
    end)
    |> sort_by_urgency()
  end

  defp build_completed_rows(obligations) do
    summaries = Obligations.event_summaries_for(obligations)

    Enum.map(obligations, fn obligation ->
      %{event_count: event_count, latest_event: latest_event} =
        Map.fetch!(summaries, obligation.id)

      %{
        obligation: obligation,
        urgency: nil,
        event_count: event_count,
        latest_event: latest_event
      }
    end)
  end

  defp summary_chips(grouped, unassigned_rows) do
    [
      %{
        key: "overdue",
        label: "overdue",
        count: length(tier_rows(grouped, :overdue)),
        badge: "badge-error",
        icon: "hero-exclamation-triangle-mini"
      },
      %{
        key: "due-soon",
        label: "due soon",
        count: length(tier_rows(grouped, :due_soon)),
        badge: "badge-warning",
        icon: nil
      },
      %{
        key: "unassigned",
        label: "unassigned",
        count: length(unassigned_rows),
        badge: "badge-secondary",
        icon: "hero-user-mini"
      },
      %{
        key: "on-track",
        label: "on track",
        count: length(tier_rows(grouped, :ok)),
        badge: "badge-ghost",
        icon: nil
      }
    ]
  end

  defp sort_by_urgency(rows) do
    Enum.sort_by(rows, fn %{obligation: o, urgency: urgency} ->
      {@urgency_rank[urgency], o.due_by}
    end)
  end

  defp format_completed_at(nil), do: "—"

  defp format_completed_at(%DateTime{} = dt) do
    dt
    |> DateTime.to_date()
    |> format_date()
  end

  defp humanize_status("in_progress"), do: "In progress"
  defp humanize_status(status), do: String.capitalize(status)

  defp status_badge_class("in_progress"), do: "badge-warning badge-soft"
  defp status_badge_class("done"), do: "badge-success badge-soft"
  defp status_badge_class("cancelled"), do: "badge-error badge-soft"
  defp status_badge_class(_), do: "badge-ghost"

  defp event_count_label(1), do: "1 event"
  defp event_count_label(count), do: "#{count} events"

  defp truncate_note(note) when is_binary(note) do
    if String.length(note) > 72, do: String.slice(note, 0, 69) <> "…", else: note
  end
end
