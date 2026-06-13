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
            {@obligation.obligation_type.name} · due {format_date(@obligation.due_by)} · {due_label(
              @obligation.due_by,
              @today
            )}
          </:subtitle>
          <:actions>
            <.urgency_badge urgency={@urgency} />
          </:actions>
        </.header>

        <section class="mt-6">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            Assignees
          </h2>
          <div class="mt-2 flex flex-wrap gap-2">
            <span class="badge badge-primary badge-soft gap-1">
              <.icon name="hero-user-mini" class="size-3" />
              {@obligation.primary_assignee.email}
            </span>
            <span :for={c <- @obligation.collaborators} class="badge badge-ghost gap-1">
              <.icon name="hero-user-group-mini" class="size-3" />
              {c.user.email}
            </span>
          </div>
        </section>

        <section :if={@required_docs != []} class="mt-6">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            Required documents
          </h2>
          <ul class="mt-2 space-y-1 text-sm">
            <li :for={{slot, satisfied?} <- @required_docs} class="flex items-center gap-2">
              <.icon
                name={if satisfied?, do: "hero-check-circle-mini", else: "hero-x-circle-mini"}
                class={["size-4", if(satisfied?, do: "text-success", else: "text-base-content/40")]}
              />
              <span class={if satisfied?, do: "", else: "text-base-content/60"}>{slot}</span>
            </li>
          </ul>
        </section>

        <section class="mt-8">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">Timeline</h2>
          <ol id="event-timeline" class="mt-3 space-y-4">
            <li
              :for={event <- @obligation.events}
              id={"event-#{event.id}"}
              data-status={event.status}
              class={["border-l-2 pl-4", event_accent(event.status)]}
            >
              <div class="flex items-center justify-between gap-3">
                <span class="font-medium">{humanize_status(event.status)}</span>
                <span class="text-xs text-base-content/50">{format_datetime(event.inserted_at)}</span>
              </div>
              <div :if={event.status_by} class="text-xs text-base-content/50">
                by {event.status_by.email}
              </div>
              <div :if={event.note} class="text-sm text-base-content/70 mt-1">{event.note}</div>
              <ul :if={event.documents != []} class="mt-2 space-y-1 text-sm">
                <li :for={doc <- event.documents} class="flex items-center gap-2">
                  <.icon name="hero-paper-clip-mini" class="size-4 text-base-content/40" />
                  <span :if={doc.document_slot} class="badge badge-xs badge-ghost">
                    {doc.document_slot}
                  </span>
                  <.link
                    href={
                      ~p"/entities/#{@current_scope.entity.slug}/obligations/#{@obligation.id}/documents/#{doc.id}"
                    }
                    target="_blank"
                    class={["link link-hover", doc.voided_at && "line-through text-base-content/40"]}
                  >
                    {file_name(doc)}
                  </.link>
                  <span :if={doc.voided_at} class="badge badge-xs badge-error">voided</span>
                </li>
              </ul>
            </li>
          </ol>
        </section>

        <section :if={@live? and @can_add_document?} class="mt-8">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            Add document
          </h2>
          <.form
            for={%{}}
            id="document-form"
            phx-change="validate_upload"
            phx-submit="add_document"
            class="mt-2 flex flex-wrap items-end gap-3"
          >
            <select
              :if={@doc_slots != []}
              id="document-slot"
              name="document_slot"
              class="select"
              required
            >
              <option value="">Choose slot…</option>
              <option :for={slot <- @doc_slots} value={slot}>{slot}</option>
            </select>
            <.live_file_input upload={@uploads.document} class="file-input" />
            <.button class="btn btn-primary btn-sm" phx-disable-with="Uploading…">Upload</.button>
          </.form>
          <p :for={err <- upload_errors(@uploads.document)} class="text-sm text-error mt-1">
            {upload_error_to_string(err)}
          </p>
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
        <section :if={length(@series) > 1} id="series-history" class="mt-8">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            Series history
          </h2>
          <ul class="mt-3 divide-y divide-base-300 rounded-box border border-base-300">
            <li
              :for={cycle <- @series}
              id={"series-cycle-#{cycle.id}"}
              class="flex items-center gap-3 p-3"
            >
              {cycle_marker(cycle, @obligation.id)}
              <div class="flex-1 text-sm">
                due {format_date(cycle.due_by)}
              </div>
              <.link
                :if={cycle.id != @obligation.id}
                navigate={~p"/entities/#{@current_scope.entity.slug}/obligations/#{cycle.id}"}
                class="link link-hover text-sm"
              >
                View
              </.link>
              <span :if={cycle.id == @obligation.id} class="text-sm text-base-content/50">
                viewing
              </span>
            </li>
          </ul>
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
     |> assign(:show_done_modal, false)
     |> assign(:recurring?, recurring?(obligation))
     |> assign(:today, today)
     |> assign(:urgency, urgency)
     |> assign(:live?, live?)
     |> allow_upload(:document, accept: :any, max_entries: 1, max_file_size: 20_000_000)
     |> assign_obligation(obligation)
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

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("add_document", params, socket) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation
    slot = params["document_slot"]

    case current_workable_event(obligation) do
      nil ->
        {:noreply, put_flash(socket, :error, "No open step to attach a document to.")}

      event ->
        results =
          consume_uploaded_entries(socket, :document, fn %{path: path}, entry ->
            upload = %Plug.Upload{
              path: path,
              filename: entry.client_name,
              content_type: entry.client_type
            }

            {:ok, Obligations.add_document(scope, obligation, event, upload, slot)}
          end)

        case results do
          [{:ok, _document}] ->
            {:noreply, reload(socket) |> put_flash(:info, "Document added.")}

          [:not_authorise] ->
            {:noreply, put_flash(socket, :error, "Not authorized.")}

          [{:error, _}] ->
            {:noreply, put_flash(socket, :error, "Could not add document.")}

          [] ->
            {:noreply, put_flash(socket, :error, "Choose a file to upload.")}
        end
    end
  end

  defp reload(socket) do
    scope = socket.assigns.current_scope
    obligation = Obligations.get_obligation!(scope, socket.assigns.obligation.id)
    assign_obligation(socket, obligation)
  end

  defp assign_obligation(socket, obligation) do
    doc_slots = parse_slots(obligation.complete_documents)
    satisfied = satisfied_slots(obligation)

    required_docs = Enum.map(doc_slots, fn slot -> {slot, MapSet.member?(satisfied, slot)} end)

    socket
    |> assign(:obligation, obligation)
    |> assign(:doc_slots, doc_slots)
    |> assign(:required_docs, required_docs)
    |> assign(:series, Obligations.list_series(obligation.series_id))
    |> assign(:can_add_document?, can_add_document?(socket.assigns.current_scope, obligation))
  end

  defp cycle_marker(cycle, current_id) do
    {label, class} =
      cond do
        cycle.id == current_id -> {"Current", "badge-primary"}
        cycle.status == "cancelled" -> {"Cancelled", "badge-error"}
        match?(%DateTime{}, cycle.completed_at) -> {"Completed", "badge-success"}
        true -> {"Live", "badge-ghost"}
      end

    assigns = %{label: label, class: class}

    ~H"""
    <span class={["badge badge-sm", @class]}>{@label}</span>
    """
  end

  defp can_add_document?(scope, obligation) do
    Authorization.can?(scope, :edit_obligation) or
      Authorization.can?(scope, :start_progress, obligation)
  end

  defp current_workable_event(obligation) do
    obligation.events
    |> Enum.filter(&(&1.status in ["open", "in_progress"]))
    |> List.last()
  end

  defp satisfied_slots(obligation) do
    obligation.events
    |> Enum.flat_map(& &1.documents)
    |> Enum.reject(& &1.voided_at)
    |> Enum.map(& &1.document_slot)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp parse_slots(nil), do: []
  defp parse_slots(""), do: []

  defp parse_slots(csv) do
    csv
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp event_accent("done"), do: "border-success"
  defp event_accent("cancelled"), do: "border-error"
  defp event_accent("in_progress"), do: "border-warning"
  defp event_accent(_), do: "border-base-300"

  defp humanize_status("in_progress"), do: "In progress"
  defp humanize_status(status), do: String.capitalize(status)

  defp upload_error_to_string(:too_large), do: "File is too large (max 20 MB)."
  defp upload_error_to_string(:too_many_files), do: "You can only upload one file at a time."
  defp upload_error_to_string(:not_accepted), do: "This file type is not accepted."
  defp upload_error_to_string(_), do: "Invalid file."

  defp assign_done_form(socket, obligation) do
    suggestion =
      if socket.assigns.recurring? do
        Recurrence.next_due_suggestion(obligation.obligation_type, obligation.due_by)
      end

    assign(
      socket,
      :done_form,
      to_form(%{"note" => "", "next_due_by" => iso_date(suggestion)}, as: :done)
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

  defp iso_date(nil), do: ""
  defp iso_date(%Date{} = date), do: Date.to_iso8601(date)
end
