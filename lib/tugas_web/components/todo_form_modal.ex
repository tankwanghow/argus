defmodule TugasWeb.TodoFormModal do
  @moduledoc """
  Shared create/edit-todo modal markup, used by the Todos pages
  (`TodoLive.Index`, `MobileLive.Todos`) and the dashboards' quick **+ Todo**
  button. Callers own the form state (`@todo_form` via `Todos.change_todo`) and
  the change/submit/cancel events; this component only renders the modal so the
  markup stays in one place. IDs are passed in to preserve each host's element ids.
  """
  use Phoenix.Component

  import TugasWeb.CoreComponents, only: [input: 1, button: 1]

  alias Phoenix.LiveView.JS

  attr :form, :any, required: true
  attr :id, :string, required: true
  attr :form_id, :string, required: true
  attr :title, :string, default: "New todo"
  attr :submit_label, :string, default: "Add todo"
  attr :variant, :atom, default: :desktop
  attr :on_change, :string, default: "validate"
  attr :on_submit, :string, default: "save"
  attr :on_cancel, :string, required: true

  def todo_form_modal(assigns) do
    assigns = assign(assigns, :mobile?, assigns.variant == :mobile)

    ~H"""
    <div id={@id} class={["modal modal-open", @mobile? && "modal-bottom"]}>
      <div class="modal-box">
        <h3 class="font-bold text-lg">{@title}</h3>
        <.form
          for={@form}
          id={@form_id}
          phx-change={@on_change}
          phx-submit={@on_submit}
          class="mt-4 space-y-3"
        >
          <.input
            field={@form[:title]}
            type="text"
            label="Title"
            required
            phx-mounted={JS.focus()}
          />
          <div :if={!@mobile?} class="modal-action">
            <button type="button" class="btn" phx-click={@on_cancel}>Cancel</button>
            <.button class="btn btn-primary" phx-disable-with="Saving…">{@submit_label}</.button>
          </div>
          <div :if={@mobile?} class="flex gap-2 pt-2">
            <button type="button" class="btn flex-1" phx-click={@on_cancel}>Cancel</button>
            <.button class="btn btn-primary flex-1" phx-disable-with="Saving…">
              {@submit_label}
            </.button>
          </div>
        </.form>
      </div>
      <div class="modal-backdrop">
        <button type="button" phx-click={@on_cancel}>close</button>
      </div>
    </div>
    """
  end
end
