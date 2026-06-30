defmodule TugasWeb.DutyLive.FormComponent do
  @moduledoc """
  Modal create-duty form, used everywhere a duty is created (dashboard, duties
  listing, mobile, and todo escalation). Owns its own form/validation/save via
  the shared `CreateForm` logic and notifies the parent LiveView with
  `{:duty_created, duty, from_todo_id}` on success so the parent can close the
  modal, flash, and reload. Render it only when open:

      <.live_component
        :if={@create_duty_open?}
        module={TugasWeb.DutyLive.FormComponent}
        id="duty-form-modal"
        current_scope={@current_scope}
        from_todo_id={@create_duty_from_todo_id}
      />
  """
  use TugasWeb, :live_component

  alias TugasWeb.DutyLive.CreateForm

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:variant, fn -> :desktop end)

    if socket.assigns[:loaded?] do
      {:ok, socket}
    else
      from_todo_id = socket.assigns[:from_todo_id]
      params = if from_todo_id, do: %{"from_todo" => from_todo_id}, else: %{}

      {:ok,
       socket
       |> assign(:loaded?, true)
       |> assign(:error, nil)
       |> CreateForm.load_form(params)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class={modal_class(@variant)}>
      <div class={box_class(@variant)}>
        <h3 class="text-lg font-bold mb-2">New duty</h3>

        <p :if={@error} class="alert alert-error text-sm mb-2">{@error}</p>

        <.form
          for={@form}
          id="duty-create-form"
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <.char_count_input field={@form[:title]} label="Title" max={60} required />
          <div class="flex items-center gap-4">
            <.input
              field={@form[:duty_type_id]}
              type="select"
              label="Type"
              options={@type_options}
              prompt="Choose a type"
              required
            />
            <div class="mt-6">
              <.input field={@form[:someday]} type="checkbox" label="No due date (Someday)" />
            </div>
            <.input
              :if={!someday?(@form)}
              field={@form[:due_by]}
              type="date"
              label="Due by"
              required
            />
          </div>
          <.input field={@form[:open_note]} type="textarea" label="Open note" required />
          <div class="fieldset">
            <.input
              field={@form[:primary_assignee_id]}
              type="select"
              label="Primary assignee"
              options={@member_options}
              prompt="Unassigned"
            />
            <label class="label" for="collaborator-ids">Also collaborating (optional)</label>
            <select
              id="collaborator-ids"
              name="duty[collaborator_ids][]"
              multiple
              class="select w-full h-24"
            >
              <option :for={{label, id} <- @member_options} value={id}>{label}</option>
            </select>
            <p class="text-xs text-base-content/50">
              Hold ⌘/Ctrl to select more than one.
            </p>
          </div>

          <div class="modal-action">
            <button type="button" class="btn" phx-click="close_create_duty">Cancel</button>
            <button type="submit" class="btn btn-primary" phx-disable-with="Creating...">
              Create duty
            </button>
          </div>
        </.form>
      </div>
      <button class="modal-backdrop" type="button" phx-click="close_create_duty" aria-label="Close" />
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"duty" => params}, socket) do
    CreateForm.validate(socket, params)
  end

  def handle_event("save", %{"duty" => params}, socket) do
    case CreateForm.create(socket, params) do
      {:ok, socket, duty} ->
        send(self(), {:duty_created, duty, socket.assigns[:from_todo_id]})
        {:noreply, socket}

      {:error, socket} ->
        {:noreply, socket}

      {:error, socket, message} ->
        {:noreply, assign(socket, :error, message)}
    end
  end

  defp someday?(form), do: Phoenix.HTML.Form.normalize_value("checkbox", form[:someday].value)

  # Mobile uses the bottom-sheet chrome that the mobile edit-duty modal uses.
  defp modal_class(:mobile), do: "modal modal-bottom modal-open"
  defp modal_class(_), do: "modal modal-open"

  defp box_class(:mobile), do: "modal-box"
  defp box_class(_), do: "modal-box max-w-xl"
end
