defmodule ArgusWeb.ObligationLive.Show do
  use ArgusWeb, :live_view

  alias Argus.Authorization
  alias Argus.Obligations
  alias Argus.Obligations.{Obligation, Recurrence, Urgency}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="obligation-show">
        <.header>
          {@obligation.title}
          <:subtitle>
            {@obligation.obligation_type.name} · due {@obligation.due_by}
          </:subtitle>
          <:actions>
            <.urgency_badge urgency={@urgency} />
          </:actions>
        </.header>

        <section class="mt-6">
          <h2 class="text-lg font-semibold">Assignees</h2>
          <p class="text-sm mt-1">{@obligation.primary_assignee.email}</p>
        </section>

        <section class="mt-8">
          <h2 class="text-lg font-semibold">Timeline</h2>
          <ol id="event-timeline" class="mt-3 space-y-3">
            <li :for={event <- @obligation.events} id={"event-#{event.id}"} class="border-l-2 pl-4">
              <div class="font-medium capitalize">{event.status}</div>
              <div :if={event.note} class="text-sm text-base-content/70">{event.note}</div>
              <ul :if={event.documents != []} class="mt-2 text-sm">
                <li :for={doc <- event.documents}>
                  {doc.document_slot || "file"} — {file_name(doc)}
                </li>
              </ul>
            </li>
          </ol>
        </section>

        <section :if={@live?} id="obligation-actions" class="mt-8 flex flex-wrap gap-2">
          <button
            :if={Authorization.can?(@current_scope, :start_progress, @obligation)}
            id="start-progress-btn"
            type="button"
            phx-click="start_progress"
            class="btn btn-outline btn-sm"
          >
            Start progress
          </button>
          <button
            :if={Authorization.can?(@current_scope, :mark_done, @obligation)}
            id="done-btn"
            type="button"
            phx-click="open_done_modal"
            class="btn btn-primary btn-sm"
          >
            Mark done
          </button>
          <button
            :if={Authorization.can?(@current_scope, :cancel_obligation)}
            id="cancel-btn"
            type="button"
            phx-click="cancel"
            class="btn btn-outline btn-error btn-sm"
          >
            Cancel
          </button>
          <button
            :if={Authorization.can?(@current_scope, :end_series)}
            id="end-series-btn"
            type="button"
            phx-click="end_series"
            class="btn btn-ghost btn-sm"
          >
            End series
          </button>
        </section>
      </div>

      <div
        :if={@show_done_modal}
        id="done-modal"
        class="modal modal-open"
      >
        <div class="modal-box">
          <h3 class="font-bold text-lg">Mark done</h3>
          <.form for={@done_form} id="done-form" phx-submit="complete">
            <.input
              :if={@recurring?}
              field={@done_form[:next_due_by]}
              type="date"
              label="Next due date"
              required
            />
            <.input
              :if={@obligation.complete_note_required}
              field={@done_form[:note]}
              type="textarea"
              label="Completion note"
              required
            />
            <div class="modal-action">
              <button type="button" class="btn" phx-click="close_done_modal">Cancel</button>
              <.button class="btn btn-primary">Complete</.button>
            </div>
          </.form>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="close_done_modal">close</button>
        </form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    obligation =
      scope
      |> Obligations.get_obligation!(id)
      |> Map.update!(:events, fn events -> Enum.sort_by(events, & &1.inserted_at, DateTime) end)

    today = Urgency.today_for(scope.entity.timezone)

    urgency = Urgency.classify(obligation.obligation_type, obligation.due_by, today)
    live? = live_cycle?(obligation)

    {:ok,
     socket
     |> assign(:obligation, obligation)
     |> assign(:urgency, urgency)
     |> assign(:today, today)
     |> assign(:live?, live?)
     |> assign(:show_done_modal, false)
     |> assign(:recurring?, recurring?(obligation))
     |> assign_done_form(obligation)}
  end

  @impl true
  def handle_event("start_progress", _params, socket) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation

    case Obligations.start_progress(scope, obligation) do
      {:ok, _} ->
        {:noreply, reload(socket) |> put_flash(:info, "Progress started.")}

      {:error, :not_open} ->
        {:noreply, put_flash(socket, :error, "Already in progress.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("open_done_modal", _params, socket) do
    {:noreply, assign(socket, :show_done_modal, true)}
  end

  def handle_event("close_done_modal", _params, socket) do
    {:noreply, assign(socket, :show_done_modal, false)}
  end

  def handle_event("complete", %{"done" => params}, socket) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation

    attrs = %{
      note: params["note"],
      next_due_by: parse_date(params["next_due_by"])
    }

    case Obligations.complete(scope, obligation, attrs) do
      {:ok, _completed, _spawned} ->
        {:noreply,
         socket
         |> put_flash(:info, "Obligation completed.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/obligations")}

      {:error, :next_due_required} ->
        {:noreply,
         put_flash(socket, :error, "Next due date is required for recurring obligations.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not complete obligation.")}

      :not_authorise ->
        {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("cancel", _params, socket) do
    scope = socket.assigns.current_scope

    case Obligations.cancel_obligation(scope, socket.assigns.obligation, %{}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Obligation cancelled.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/obligations")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not cancel.")}
    end
  end

  def handle_event("end_series", _params, socket) do
    scope = socket.assigns.current_scope

    case Obligations.end_series(scope, socket.assigns.obligation, %{}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Series ended.")
         |> push_navigate(to: ~p"/entities/#{scope.entity.slug}/obligations")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not end series.")}
    end
  end

  defp reload(socket) do
    scope = socket.assigns.current_scope
    obligation = Obligations.get_obligation!(scope, socket.assigns.obligation.id)
    assign(socket, :obligation, obligation)
  end

  defp assign_done_form(socket, obligation) do
    suggestion =
      if socket.assigns.recurring? do
        Recurrence.next_due_suggestion(obligation.obligation_type, obligation.due_by)
      end

    assign(
      socket,
      :done_form,
      to_form(%{"note" => "", "next_due_by" => format_date(suggestion)}, as: :done)
    )
  end

  defp recurring?(obligation) do
    Recurrence.recurring?(obligation.obligation_type) and is_nil(obligation.series_ended_at)
  end

  defp live_cycle?(%Obligation{status: "active", completed_at: nil}), do: true
  defp live_cycle?(_), do: false

  defp file_name(%{file: file}) when is_map(file) do
    Map.get(file, "original") || Map.get(file, :original) || "file"
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp format_date(nil), do: ""
  defp format_date(%Date{} = date), do: Date.to_iso8601(date)
end
