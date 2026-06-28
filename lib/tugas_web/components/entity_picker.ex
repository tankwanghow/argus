defmodule TugasWeb.EntityPicker do
  @moduledoc false
  use TugasWeb, :html

  attr :memberships, :list, required: true
  attr :form, :any, required: true
  attr :editing_entity_id, :any, default: nil
  attr :edit_form, :any, default: nil
  attr :mobile?, :boolean, default: false

  def picker(assigns) do
    ~H"""
    <div id="entity-picker" class="mx-auto max-w-2xl">
      <.header>
        Your entities
        <:subtitle>Pick an entity to enter, or create a new one.</:subtitle>
      </.header>

      <ul id="entities" class="mt-6 divide-y divide-base-300">
        <li
          :for={{entity, membership} <- @memberships}
          id={"entity-#{entity.id}"}
          class="py-3"
        >
          <div class="flex items-center justify-between gap-3">
            <div class="flex items-center gap-2 min-w-0">
              <span class="font-medium wrap">{entity.name}</span>
              <span
                :if={membership.is_default}
                class="badge badge-sm badge-primary shrink-0"
                title="Your default entity"
              >
                Default
              </span>
            </div>
            <div class="flex items-center gap-1 shrink-0">
              <button
                :if={membership.role == "admin" and @editing_entity_id != entity.id}
                id={"edit-entity-#{entity.id}"}
                type="button"
                phx-click="edit_entity"
                phx-value-id={entity.id}
                class="btn btn-ghost btn-xs"
              >
                Edit
              </button>
              <.link href={enter_entity_path(entity.slug, @mobile?)} class="btn btn-primary btn-sm">
                Enter
              </.link>
            </div>
          </div>

          <.form
            :if={@editing_entity_id == entity.id && @edit_form}
            for={@edit_form}
            id={"edit-entity-form-#{entity.id}"}
            phx-submit="save_entity"
            phx-change="validate_edit"
            class="mt-3 space-y-3 rounded-box border border-base-300 bg-base-200/30 p-3"
          >
            <input type="hidden" name="entity_id" value={entity.id} />
            <.input
              field={@edit_form[:name]}
              type="text"
              label="Name"
              id={"edit-entity-name-#{entity.id}"}
              required
            />
            <.input
              field={@edit_form[:slug]}
              type="text"
              label="Slug"
              id={"edit-entity-slug-#{entity.id}"}
              class="w-full input font-mono"
              required
            />
            <.input
              field={@edit_form[:timezone]}
              type="select"
              label="Timezone"
              id={"edit-entity-timezone-#{entity.id}"}
              options={timezone_options()}
            />
            <.input
              field={@edit_form[:country_code]}
              type="select"
              label="Public holidays (country)"
              id={"edit-entity-country-#{entity.id}"}
              options={country_options()}
            />
            <.input
              field={@edit_form[:holiday_region]}
              type="select"
              label="State / territory (Malaysia)"
              id={"edit-entity-holiday-region-#{entity.id}"}
              options={malaysia_region_options()}
            />
            <div class="flex gap-2">
              <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_edit">
                Cancel
              </button>
              <.button phx-disable-with="Saving..." class="btn btn-primary btn-sm">
                Save changes
              </.button>
            </div>
          </.form>
        </li>
        <li :if={@memberships == []} class="py-6 text-base-content/60">
          No entities yet.
        </li>
      </ul>

      <div class="mt-10">
        <.header>Create an entity</.header>
        <.form
          for={@form}
          id="new-entity-form"
          phx-submit="save"
          phx-change="validate"
          class="mt-4 space-y-3"
        >
          <.input field={@form[:name]} type="text" label="Name" id="new-entity-name" required />
          <.input
            field={@form[:slug]}
            type="text"
            label="Slug"
            id="new-entity-slug"
            class="w-full input font-mono"
            required
            placeholder="lowercase-with-hyphens"
          />
          <.button phx-disable-with="Creating..." class="btn btn-primary w-full sm:w-auto">
            Create entity
          </.button>
        </.form>
      </div>
    </div>
    """
  end

  defp enter_entity_path(slug, true), do: ~p"/m/#{slug}"
  defp enter_entity_path(slug, false), do: ~p"/entities/#{slug}"

  defp timezone_options do
    [
      {"Asia/Kuala_Lumpur", "Asia/Kuala_Lumpur"},
      {"Asia/Singapore", "Asia/Singapore"},
      {"Asia/Tokyo", "Asia/Tokyo"},
      {"UTC", "UTC"},
      {"Europe/London", "Europe/London"},
      {"America/New_York", "America/New_York"}
    ]
  end

  defp country_options, do: Tugas.Entities.Country.options()

  defp malaysia_region_options, do: Tugas.Entities.MalaysiaRegion.options()
end
