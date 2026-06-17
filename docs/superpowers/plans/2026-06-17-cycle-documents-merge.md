# Unified Documents View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the obligation Documents modal into two non-redundant surfaces — required completion files at cycle level, supporting files per step — each owning its voided files, which stay downloadable.

**Architecture:** Two new function components (`ObligationCompletionDocuments`, `ObligationStepFiles`) replace the two existing ones (`ObligationDocumentUpload`, `ObligationDocumentList`). Pure classification helpers in `DocumentHelpers` partition a cycle's documents into required-slot files (live + voided) and per-step other files (live + voided). Both desktop and mobile LiveViews wire the surfaces; the context layer is reused unchanged.

**Tech Stack:** Elixir/Phoenix 1.8, LiveView 1.2 (function components, colocated hooks, `allow_upload`/`live_file_input`), Tailwind v4 + daisyUI 5, ExUnit + `Phoenix.LiveViewTest`.

## Global Constraints

- Unauthorized context calls return `:not_authorise` (never raise).
- Uploads: single `:document` upload config per LiveView; `accept: :any`, `max_entries: ArgusWeb.LiveUpload.max_document_entries()`, `max_file_size: 20_000_000`, `auto_upload: true`. Only one Documents modal is open at a time, so both surfaces share that one config.
- Slots are immutable after upload; there is no Replace and no post-upload slot editing (already shipped). Do not reintroduce them.
- A document is **required** iff its `document_slot` is in the obligation's **current snapshot** `complete_documents`; otherwise it is **other/supporting** (nil slot or stale slot). Classify at render time; never mutate document rows to reclassify.
- Completion rules unchanged: a required slot is satisfied by one non-voided document with that slot name, counted cycle-wide.
- `mix precommit` must pass before a task is considered done (it runs `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`).
- Run from repo root `/home/tankwanghow/Projects/elixir/argus`. Work happens on branch `cycle-documents-merge`.

---

## File Structure

- **Create** `lib/argus_web/components/obligation_completion_documents.ex` — Surface A component (cycle-level required slots + voided-required section + per-slot uploader for unsatisfied slots). Hosts the colocated `SlotFilePicker` hook.
- **Create** `lib/argus_web/components/obligation_step_files.ex` — Surface B component (one event's live other files + voided-other + additional-file uploader).
- **Modify** `lib/argus_web/live/obligation_live/document_helpers.ex` — add pure classification helpers.
- **Modify** `lib/argus_web/live/obligation_live/show.ex` — desktop wiring: one cycle "Completion documents" button + modal (Surface A), per-event "Files" button + modal (Surface B), state, handlers, upload-target resolution.
- **Modify** `lib/argus_web/live/mobile_live/obligation_show.ex` — mobile wiring mirroring desktop (id prefix `m-`).
- **Modify** `lib/argus_web/controllers/document_controller.ex` — allow downloading voided files.
- **Delete** `lib/argus_web/components/obligation_document_upload.ex`, `lib/argus_web/components/obligation_document_list.ex`.
- **Tests** `test/argus_web/live/obligation_live/document_helpers_test.exs` (new), `test/argus_web/controllers/document_controller_test.exs` (extend), `test/argus_web/live/obligation_live_test.exs` (extend/migrate), `test/argus_web/live/mobile_live_test.exs` (extend).

---

## Task 1: Document classification helpers

**Files:**
- Modify: `lib/argus_web/live/obligation_live/document_helpers.ex`
- Test: `test/argus_web/live/obligation_live/document_helpers_test.exs` (create)

**Interfaces:**
- Consumes: `Argus.Obligations.EventDocument` (`:document_slot`, `:voided_at`).
- Produces:
  - `parse_slots(csv :: String.t() | nil) :: [String.t()]`
  - `completion_view(documents :: [EventDocument.t()], required_slots :: [String.t()]) :: {slot_rows, voided_required}` where `slot_rows :: [{String.t(), EventDocument.t() | nil}]` (one tuple per required slot, in given order; second element is the live file or `nil`), `voided_required :: [EventDocument.t()]`.
  - `step_files(event_documents :: [EventDocument.t()], required_slots :: [String.t()]) :: {live_other, voided_other}` (both `[EventDocument.t()]`; "other" = slot nil or not in required_slots).

- [ ] **Step 1: Write the failing test**

Create `test/argus_web/live/obligation_live/document_helpers_test.exs`:

```elixir
defmodule ArgusWeb.ObligationLive.DocumentHelpersTest do
  use ExUnit.Case, async: true

  alias ArgusWeb.ObligationLive.DocumentHelpers, as: H
  alias Argus.Obligations.EventDocument

  defp doc(slot, voided? \\ false) do
    %EventDocument{
      id: Ecto.UUID.generate(),
      document_slot: slot,
      voided_at: if(voided?, do: ~U[2026-06-16 08:33:00Z], else: nil)
    }
  end

  test "parse_slots splits and trims, dropping blanks" do
    assert H.parse_slots("receipt, form ,") == ["receipt", "form"]
    assert H.parse_slots("") == []
    assert H.parse_slots(nil) == []
  end

  test "completion_view maps each required slot to its live file or nil" do
    receipt = doc("receipt")
    form_voided = doc("form", true)
    other = doc(nil)

    {slot_rows, voided_required} =
      H.completion_view([receipt, form_voided, other], ["receipt", "form"])

    assert slot_rows == [{"receipt", receipt}, {"form", nil}]
    assert voided_required == [form_voided]
  end

  test "step_files returns this event's live and voided other files (slot nil or stale)" do
    live_no_slot = doc(nil)
    live_stale = doc("old_slot")
    live_required = doc("receipt")
    voided_no_slot = doc(nil, true)
    voided_required = doc("receipt", true)

    {live_other, voided_other} =
      H.step_files(
        [live_no_slot, live_stale, live_required, voided_no_slot, voided_required],
        ["receipt"]
      )

    assert live_other == [live_no_slot, live_stale]
    assert voided_other == [voided_no_slot]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus_web/live/obligation_live/document_helpers_test.exs`
Expected: FAIL — `function H.parse_slots/1 (or completion_view/2, step_files/2) is undefined`.

- [ ] **Step 3: Write minimal implementation**

In `lib/argus_web/live/obligation_live/document_helpers.ex`, add `alias Argus.Obligations.EventDocument` under the `@moduledoc` and append these functions (keep the existing `upload_event/1`):

```elixir
  def parse_slots(nil), do: []
  def parse_slots(""), do: []

  def parse_slots(csv) when is_binary(csv) do
    csv
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Partitions cycle documents for the cycle-level required view.
  """
  def completion_view(documents, required_slots) do
    required = MapSet.new(required_slots)
    live = Enum.reject(documents, & &1.voided_at)

    slot_rows =
      Enum.map(required_slots, fn slot ->
        {slot, Enum.find(live, &(&1.document_slot == slot))}
      end)

    voided_required =
      documents
      |> Enum.filter(& &1.voided_at)
      |> Enum.filter(&(&1.document_slot in required))

    {slot_rows, voided_required}
  end

  @doc """
  Partitions one event's documents into live/voided "other" (supporting) files.
  """
  def step_files(event_documents, required_slots) do
    required = MapSet.new(required_slots)
    other? = fn doc -> is_nil(doc.document_slot) or doc.document_slot not in required end

    live_other = event_documents |> Enum.reject(& &1.voided_at) |> Enum.filter(other?)
    voided_other = event_documents |> Enum.filter(& &1.voided_at) |> Enum.filter(other?)

    {live_other, voided_other}
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/argus_web/live/obligation_live/document_helpers_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/argus_web/live/obligation_live/document_helpers.ex test/argus_web/live/obligation_live/document_helpers_test.exs
git commit -m "feat: document classification helpers for unified Documents view

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Allow downloading voided files

**Files:**
- Modify: `lib/argus_web/controllers/document_controller.ex:11-25`
- Test: `test/argus_web/controllers/document_controller_test.exs`

**Interfaces:**
- Consumes: `Argus.Obligations.void_document/4` (existing), `Argus.Uploads.path/1` (existing).
- Produces: `GET /entities/:entity_slug/obligations/:obligation_id/documents/:id` now serves a voided file (200) as long as the file exists on disk.

- [ ] **Step 1: Write the failing test**

Find the existing download test for context (`grep -n "send_download\|disposition\|defmodule" test/argus_web/controllers/document_controller_test.exs`). Add this test inside the module (use the file's existing setup/fixtures; adapt fixture names to those already used in that file):

```elixir
  test "serves a voided document so it can still be downloaded", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = Argus.ObligationsFixtures.type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Argus.Obligations.create_obligation(manager, %{
        title: "EPF",
        obligation_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    event = hd(Argus.Obligations.list_events(obligation))

    {:ok, document} =
      Argus.Obligations.add_document(
        manager,
        obligation,
        event,
        Argus.ObligationsFixtures.upload_fixture("receipt.pdf"),
        "receipt"
      )

    # Void it (admin, with reason).
    {:ok, _} =
      Argus.Obligations.void_document(manager, obligation, document, %{reason: "wrong file"})

    conn =
      get(
        conn,
        ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents/#{document.id}"
      )

    assert conn.status == 200
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus_web/controllers/document_controller_test.exs`
Expected: FAIL — the voided document returns 404 ("Not found"), so `conn.status` is 404, not 200.

- [ ] **Step 3: Write minimal implementation**

In `lib/argus_web/controllers/document_controller.ex`, change the guard in `show/2` to drop the voided check (keep the file-existence check):

```elixir
    if File.exists?(Uploads.path(document)) do
      send_download(conn, {:file, Uploads.path(document)},
        filename: original_filename(document),
        disposition: :inline
      )
    else
      conn |> put_status(:not_found) |> text("Not found")
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/argus_web/controllers/document_controller_test.exs`
Expected: PASS (all tests in the file).

- [ ] **Step 5: Commit**

```bash
git add lib/argus_web/controllers/document_controller.ex test/argus_web/controllers/document_controller_test.exs
git commit -m "feat: allow downloading voided documents

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Surface A — Completion Documents (component + desktop wiring)

**Files:**
- Create: `lib/argus_web/components/obligation_completion_documents.ex`
- Modify: `lib/argus_web/live/obligation_live/show.ex` (modal render ~338-378; mount assigns ~548-551; handlers for open/close/select/clear/add; `assign_obligation`; `open_documents_from_done`)
- Test: `test/argus_web/live/obligation_live_test.exs`

**Interfaces:**
- Consumes: `DocumentHelpers.completion_view/2`, `DocumentHelpers.parse_slots/1`, `DocumentHelpers.upload_event/1`; `Argus.Obligations.{add_document/5, delete_document/3, void_document/4, document_deletable?/3, document_voidable?/3, document_void_reason_required?/1}`; `ArgusWeb.LiveUpload`.
- Produces (component): `ArgusWeb.ObligationCompletionDocuments.completion_documents/1` with assigns `obligation, current_scope, entity_slug, documents, required_slots, uploads, upload_slot_target, upload_slot_entries, uploadable?, voiding_document_id, void_reason_required?, id_prefix` (default `""`).
- Produces (LiveView events): `open_completion_modal`, `close_completion_modal`, `select_upload_slot` (`%{"slot" => slot}`), `clear_upload_slot` (`%{"slot" => slot}`), `validate_upload`, `add_document` (`%{"slot" => slot}` — no event_id; resolves workable event), `delete_document`, `void_document`, `confirm_void_document`, `cancel_void_document`.
- Produces (LiveView assign): boolean `show_completion_modal`.

- [ ] **Step 1: Write the failing test**

Add to `test/argus_web/live/obligation_live_test.exs` (it already has `setup :register_and_log_in_user`, imports `Phoenix.LiveViewTest` and `Argus.ObligationsFixtures`, aliases `Argus.Obligations`):

```elixir
  test "completion modal: satisfied slot shows file, unsatisfied shows uploader", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    member = member_fixture(manager.entity)
    type = type_fixture(manager.entity, complete_documents: "receipt,form")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF June",
        obligation_type_id: type.id,
        primary_assignee_id: member.id,
        due_by: ~D[2026-06-30],
        open_note: "EPF opened"
      })

    obligation = Obligations.get_obligation!(manager, obligation.id)
    [open_event] = Enum.filter(obligation.events, &(&1.status == "open"))

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#open-completion-modal") |> render_click()

    # Upload into the "receipt" slot from the cycle modal (no event id in the form).
    view |> element("#select-slot-receipt") |> render_click()

    file =
      file_input(view, "#completion-upload-form", :document, [
        %{name: "receipt.pdf", content: "scan", type: "application/pdf"}
      ])

    render_upload(file, "receipt.pdf")
    view |> form("#completion-upload-form", %{"picker_slot" => "receipt"}) |> render_change()
    view |> element("#upload-slot-receipt") |> render_click()

    # receipt satisfied (shows file + Delete), form still unsatisfied (shows uploader).
    obligation = Obligations.get_obligation!(manager, obligation.id)
    [open_event] = Enum.filter(obligation.events, &(&1.status == "open"))
    doc = hd(open_event.documents)

    assert has_element?(view, "#completion-slot-receipt", "receipt.pdf")
    assert has_element?(view, "#delete-doc-#{doc.id}")
    assert has_element?(view, "#select-slot-form")
    # the file attached to the cycle's workable (open) event
    assert doc.document_slot == "receipt"
  end

  test "completion modal: voided required file shows in voided section, downloadable", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF",
        obligation_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    event = hd(Obligations.list_events(obligation))
    {:ok, doc} = Obligations.add_document(manager, obligation, event, upload_fixture("r.pdf"), "receipt")
    {:ok, _} = Obligations.void_document(manager, obligation, doc, %{reason: "wrong"})

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#open-completion-modal") |> render_click()

    assert has_element?(view, "#completion-voided", "r.pdf")
    assert has_element?(view, "#voided-doc-#{doc.id} a[href*='/documents/#{doc.id}']")
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus_web/live/obligation_live_test.exs -k "completion modal"` (or by line numbers).
Expected: FAIL — `#open-completion-modal` element not found (button/modal don't exist yet).

- [ ] **Step 3: Create the Surface A component**

Create `lib/argus_web/components/obligation_completion_documents.ex`. Use the same daisyUI classes/idioms as the (to-be-deleted) `obligation_document_upload.ex` and `obligation_document_list.ex` for visual consistency; the structure, ids, and events below are required exactly.

```elixir
defmodule ArgusWeb.ObligationCompletionDocuments do
  @moduledoc """
  Cycle-level required completion documents: one row per required slot (live file
  inline, or an uploader if missing) plus a voided-required section. All file
  management for required slots lives here; slots are immutable after upload.
  """
  use Phoenix.Component

  import ArgusWeb.CoreComponents

  alias Argus.Obligations
  alias ArgusWeb.LiveUpload

  attr :obligation, :map, required: true
  attr :current_scope, :map, required: true
  attr :entity_slug, :string, required: true
  attr :documents, :list, required: true
  attr :required_slots, :list, required: true
  attr :uploads, :map, required: true
  attr :upload_slot_target, :any, default: nil
  attr :upload_slot_entries, :map, default: %{}
  attr :uploadable?, :boolean, required: true
  attr :voiding_document_id, :any, default: nil
  attr :void_reason_required?, :boolean, default: false
  attr :id_prefix, :string, default: ""

  def completion_documents(assigns) do
    {slot_rows, voided} =
      ArgusWeb.ObligationLive.DocumentHelpers.completion_view(
        assigns.documents,
        assigns.required_slots
      )

    assigns =
      assigns
      |> assign(:slot_rows, slot_rows)
      |> assign(:voided, voided)
      |> assign(:form_id, "#{assigns.id_prefix}completion-upload-form")

    ~H"""
    <section id={"#{@id_prefix}completion-docs"} class="space-y-3">
      <div :if={@slot_rows == []} class="text-sm text-base-content/50">
        This obligation type has no required completion documents.
      </div>

      <div class="argus-meta-label">Completion documents</div>

      <ul class="divide-y divide-base-300 rounded-box border border-base-300">
        <li
          :for={{slot, live} <- @slot_rows}
          id={"#{@id_prefix}completion-slot-#{slot}"}
          class="px-2.5 py-2 text-sm"
        >
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
            <.icon
              name={if(live, do: "hero-check-circle-mini", else: "hero-x-circle-mini")}
              class={["size-4 shrink-0", if(live, do: "text-success", else: "text-warning")]}
            />
            <span class="font-medium">{slot}</span>

            <.link
              :if={live}
              href={"/entities/#{@entity_slug}/obligations/#{@obligation.id}/documents/#{live.id}"}
              target="_blank"
              class="link link-hover truncate max-w-[12rem]"
            >
              {file_name(live)}
            </.link>
            <span :if={live} class="text-xs text-base-content/50">
              {format_datetime(live.inserted_at)}
            </span>

            <span :if={not live} class="badge badge-ghost badge-xs badge-soft">Not uploaded</span>

            <div class="ml-auto flex items-center gap-1">
              <button
                :if={live && Obligations.document_deletable?(@current_scope, @obligation, live)}
                id={"#{@id_prefix}delete-doc-#{live.id}"}
                type="button"
                phx-click="delete_document"
                phx-value-document_id={live.id}
                class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 text-error"
              >
                Delete
              </button>
              <button
                :if={
                  live && @voiding_document_id != live.id &&
                    Obligations.document_voidable?(@current_scope, @obligation, live)
                }
                id={"#{@id_prefix}void-doc-#{live.id}"}
                type="button"
                phx-click="void_document"
                phx-value-document_id={live.id}
                class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 text-error"
              >
                Void
              </button>
            </div>
          </div>

          <.void_form
            :if={live && @voiding_document_id == live.id}
            doc={live}
            void_reason_required?={@void_reason_required?}
            id_prefix={@id_prefix}
          />

          <.slot_uploader
            :if={not live and @uploadable?}
            slot={slot}
            id_prefix={@id_prefix}
            pending_entry={LiveUpload.entry_for_slot(@uploads, @upload_slot_entries, slot)}
          />
        </li>
      </ul>

      <section :if={@voided != []} id={"#{@id_prefix}completion-voided"} class="space-y-1">
        <div class="argus-meta-label">Voided required files</div>
        <ul class="divide-y divide-base-300 rounded-box border border-base-300">
          <li
            :for={doc <- @voided}
            id={"#{@id_prefix}voided-doc-#{doc.id}"}
            class="px-2.5 py-2 text-sm"
          >
            <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
              <.icon name="hero-paper-clip-mini" class="size-3.5 text-base-content/40 shrink-0" />
              <.link
                href={"/entities/#{@entity_slug}/obligations/#{@obligation.id}/documents/#{doc.id}"}
                target="_blank"
                class="link link-hover truncate max-w-[12rem] line-through text-base-content/40"
              >
                {file_name(doc)}
              </.link>
              <span :if={doc.document_slot} class="badge badge-xs badge-ghost">{doc.document_slot}</span>
              <span class="badge badge-xs badge-error">voided</span>
              <span class="text-xs text-base-content/50">{format_datetime(doc.inserted_at)}</span>
            </div>
            <p :if={doc.void_reason} class="text-xs text-base-content/50 mt-1 pl-5">
              Void reason: {doc.void_reason}
            </p>
          </li>
        </ul>
      </section>

      <.upload_form
        :if={@uploadable?}
        form_id={@form_id}
        uploads={@uploads}
        upload_slot_target={@upload_slot_target}
        id_prefix={@id_prefix}
      />

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SlotFilePicker">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const panel = this.el.closest("section")
              const form = panel?.querySelector("[data-upload-form]")
              if (!form) return
              const slot = this.el.dataset.slot
              const pickerInput = form.querySelector("[name='picker_slot']")
              const slotInput = form.querySelector("[name='document_slot']")
              if (pickerInput) pickerInput.value = slot
              if (slotInput) { slotInput.disabled = false; slotInput.value = slot }
              const fileInput = form.querySelector("input[type='file']")
              if (fileInput) fileInput.click()
            })
          }
        }
      </script>
    </section>
    """
  end

  attr :slot, :string, required: true
  attr :id_prefix, :string, required: true
  attr :pending_entry, :any, default: nil

  defp slot_uploader(assigns) do
    assigns = assign(assigns, :ready?, LiveUpload.entry_ready?(assigns.pending_entry))

    ~H"""
    <div class="mt-2 flex flex-wrap items-center gap-2 border-t border-base-300/80 pt-2">
      <%= if @pending_entry do %>
        <span class="text-sm font-medium truncate min-w-0 flex-1">{@pending_entry.client_name}</span>
        <button
          id={"#{@id_prefix}upload-slot-#{@slot}"}
          type="button"
          phx-click="add_document"
          phx-value-slot={@slot}
          disabled={not @ready?}
          class={["btn btn-primary btn-xs h-7 min-h-7 shrink-0", not @ready? && "btn-disabled"]}
          phx-disable-with="Saving…"
        >
          Upload {@slot}
        </button>
        <button
          type="button"
          phx-click="clear_upload_slot"
          phx-value-slot={@slot}
          class="btn btn-ghost btn-xs h-7 min-h-7 shrink-0"
        >
          Cancel
        </button>
      <% else %>
        <button
          id={"#{@id_prefix}select-slot-#{@slot}"}
          type="button"
          phx-hook=".SlotFilePicker"
          data-slot={@slot}
          phx-click="select_upload_slot"
          phx-value-slot={@slot}
          class="btn btn-primary btn-xs h-7 min-h-7 ml-auto"
        >
          Choose file
        </button>
      <% end %>
    </div>
    """
  end

  attr :form_id, :string, required: true
  attr :uploads, :map, required: true
  attr :upload_slot_target, :any, default: nil
  attr :id_prefix, :string, required: true

  defp upload_form(assigns) do
    ~H"""
    <.form
      for={%{}}
      id={@form_id}
      data-upload-form
      phx-change="validate_upload"
      phx-submit="add_document"
      class="sr-only"
    >
      <input type="hidden" name="picker_slot" value={picker_value(@upload_slot_target)} />
      <input
        type="hidden"
        name="document_slot"
        value={slot_value(@upload_slot_target)}
        disabled={@upload_slot_target in [nil, :additional]}
      />
      <.live_file_input upload={@uploads.document} class="sr-only" />
    </.form>
    """
  end

  attr :doc, :map, required: true
  attr :void_reason_required?, :boolean, required: true
  attr :id_prefix, :string, required: true

  defp void_form(assigns) do
    ~H"""
    <.form
      for={%{}}
      id={"#{@id_prefix}void-form-#{@doc.id}"}
      phx-submit="confirm_void_document"
      class="mt-2 pl-5 space-y-2"
    >
      <input type="hidden" name="document_id" value={@doc.id} />
      <.input :if={@void_reason_required?} name="reason" type="text" label="Reason for voiding" required />
      <div class="flex flex-wrap gap-2">
        <.button class="btn btn-error btn-xs" phx-disable-with="Voiding…">Confirm void</.button>
        <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_void_document">Cancel</button>
      </div>
    </.form>
    """
  end

  defp picker_value(slot) when is_binary(slot), do: slot
  defp picker_value(_), do: ""
  defp slot_value(slot) when is_binary(slot), do: slot
  defp slot_value(_), do: ""

  defp file_name(%{file: file}) when is_map(file) do
    Map.get(file, "original") || Map.get(file, :original) || "file"
  end
end
```

- [ ] **Step 4: Wire Surface A into the desktop LiveView render**

In `lib/argus_web/live/obligation_live/show.ex`:

(a) Add an import near the top with the other imports/aliases:
```elixir
  import ArgusWeb.ObligationCompletionDocuments
```

(b) Replace the documents modal block (currently `lib/argus_web/live/obligation_live/show.ex:338-378`, the `<div :if={@documents_modal_event} ...>...</div>`) with the cycle completion modal:
```elixir
      <div :if={@show_completion_modal} id="completion-modal" class="modal modal-open">
        <div class="modal-box max-w-lg">
          <h3 class="font-bold text-lg">Completion documents</h3>
          <div class="mt-3">
            <.completion_documents
              obligation={@obligation}
              current_scope={@current_scope}
              entity_slug={@current_scope.entity.slug}
              documents={cycle_documents(@obligation)}
              required_slots={@doc_slots}
              uploads={@uploads}
              upload_slot_target={@upload_slot_target}
              upload_slot_entries={@upload_slot_entries}
              uploadable?={@can_add_document? and @live?}
              voiding_document_id={@voiding_document_id}
              void_reason_required?={@void_reason_required?}
            />
          </div>
          <div class="modal-action mt-2">
            <button type="button" class="btn" phx-click="close_completion_modal">Close</button>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="close_completion_modal">close</button>
        </form>
      </div>
```

(c) Add a "Completion documents" button to the obligation header/action area. Place it near the existing action buttons (e.g. just above the Timeline `<section class="argus-section">` at `:156`):
```elixir
        <button
          id="open-completion-modal"
          type="button"
          phx-click="open_completion_modal"
          class="btn btn-outline btn-sm gap-1"
        >
          <.icon name="hero-paper-clip-mini" class="size-4" /> Completion documents
        </button>
```

(d) Add a private helper near `assign_obligation`:
```elixir
  defp cycle_documents(obligation) do
    Enum.flat_map(obligation.events, & &1.documents)
  end
```

- [ ] **Step 5: Wire Surface A state + handlers**

In `lib/argus_web/live/obligation_live/show.ex`:

(a) In `mount` (the assigns block around `:548-551`), replace
```elixir
     |> assign(:documents_modal_event_id, nil)
     |> assign(:documents_modal_event, nil)
```
with
```elixir
     |> assign(:show_completion_modal, false)
```
(Leave `upload_slot_target`/`upload_slot_entries`/`voiding_document_id` assigns as-is.)

(b) Replace the `open_documents_modal` and `close_documents_modal` handlers (`:867-889`) with:
```elixir
  def handle_event("open_completion_modal", _params, socket) do
    {:noreply, assign(socket, :show_completion_modal, true)}
  end

  def handle_event("close_completion_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_completion_modal, false)
     |> assign(:upload_slot_target, nil)
     |> ArgusWeb.LiveUpload.clear_all_slot_entries()
     |> assign(:voiding_document_id, nil)}
  end
```

(c) Replace the `select_upload_slot` handler (`:891-900`) with a slot-only version (Surface A has no event id):
```elixir
  def handle_event("select_upload_slot", %{"slot" => slot}, socket) do
    target = if slot == "additional", do: :additional, else: slot
    {:noreply, assign(socket, :upload_slot_target, target)}
  end
```
(Keep `clear_upload_slot` and `validate_upload` as they are.)

(d) Replace the `add_document` handler so it resolves the workable event itself and (for Surface B in Task 4) accepts an optional `event_id`. Locate the current `add_document` handler and replace it with:
```elixir
  def handle_event("add_document", params, socket) do
    scope = socket.assigns.current_scope
    obligation = socket.assigns.obligation
    slot = params["slot"]
    document_slot = if slot in [nil, "additional"], do: nil, else: slot
    ref = Map.get(socket.assigns.upload_slot_entries, ArgusWeb.LiveUpload.slot_key(slot || "additional"))

    event =
      case params["event_id"] do
        nil -> DocumentHelpers.upload_event(obligation.events)
        id -> find_event(obligation.events, id)
      end

    with %Event{} = event <- event,
         ref when not is_nil(ref) <- ref do
      case consume_slot_upload(socket, ref, scope, obligation, event, document_slot) do
        {:ok, _document} ->
          {:noreply,
           socket
           |> ArgusWeb.LiveUpload.clear_slot_entry(slot || "additional")
           |> assign(:upload_slot_target, nil)
           |> reload()
           |> put_flash(:info, "Document added.")}

        {:error, :not_authorise} ->
          {:noreply, put_flash(socket, :error, "Not authorized.")}

        {:error, :upload_failed} ->
          {:noreply, put_flash(socket, :error, "Could not add document.")}

        {:error, :no_entry} ->
          {:noreply, put_flash(socket, :error, "Choose a file to upload.")}

        {:error, :not_ready} ->
          {:noreply, put_flash(socket, :error, "File is still uploading. Wait a moment and try again.")}
      end
    else
      nil -> {:noreply, put_flash(socket, :error, "No step available to attach documents to.")}
      _ -> {:noreply, put_flash(socket, :error, "Choose a file to upload.")}
    end
  end
```
Note: `Event` is already aliased in this module; `consume_slot_upload/6`, `reload/1`, `find_event/2` already exist. The previous `add_document` removed `reopen_documents_modal/2`; the completion modal needs no reopen (it stays open via the boolean), so calls to `reopen_documents_modal` in `add_document` are dropped here.

(e) Update `open_documents_from_done` (`:716-728`) to open the completion modal instead of the per-event modal:
```elixir
  def handle_event("open_documents_from_done", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_done_modal, false)
     |> assign(:show_completion_modal, true)
     |> assign(:upload_slot_target, nil)}
  end
```

(f) Remove `:required_docs` no longer being needed for the modal? It is still used by the done checklist (`done_document_checklist`), so KEEP `@doc_slots`/`@required_docs` assigns in `assign_obligation`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `mix test test/argus_web/live/obligation_live_test.exs -k "completion modal"`
Expected: PASS for the two new tests. (Other tests in the file may still reference removed per-event document ids — those are migrated in Task 6.)

- [ ] **Step 7: Commit**

```bash
git add lib/argus_web/components/obligation_completion_documents.ex lib/argus_web/live/obligation_live/show.ex test/argus_web/live/obligation_live_test.exs
git commit -m "feat: cycle-level Completion Documents surface (desktop)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Surface B — Step Files (component + desktop wiring)

**Files:**
- Create: `lib/argus_web/components/obligation_step_files.ex`
- Modify: `lib/argus_web/live/obligation_live/show.ex` (timeline doc button ~171-180; add step-files modal; add open/close handlers + `step_files_modal_event_id` state; `add_document` already accepts `event_id`)
- Test: `test/argus_web/live/obligation_live_test.exs`

**Interfaces:**
- Consumes: `DocumentHelpers.step_files/2`, `DocumentHelpers.parse_slots/1`; `Argus.Obligations.{document_deletable?/3, document_voidable?/3}`; `ArgusWeb.LiveUpload`.
- Produces (component): `ArgusWeb.ObligationStepFiles.step_files/1` with assigns `event, obligation, current_scope, entity_slug, required_slots, uploads, upload_slot_target, upload_slot_entries, uploadable?, voiding_document_id, void_reason_required?, id_prefix`.
- Produces (LiveView events): `open_step_files` (`%{"event_id" => id}`), `close_step_files`; reuses `add_document` (with `event_id` + `slot: "additional"`), `select_upload_slot`, `clear_upload_slot`, `validate_upload`, `delete_document`, `void_document`, `confirm_void_document`, `cancel_void_document`.
- Produces (assign): `step_files_modal_event_id`.

- [ ] **Step 1: Write the failing test**

Add to `test/argus_web/live/obligation_live_test.exs`:

```elixir
  test "step files modal: additional (no-slot) file appears per step, not in completion view", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF",
        obligation_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    obligation = Obligations.get_obligation!(manager, obligation.id)
    [open_event] = Enum.filter(obligation.events, &(&1.status == "open"))

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#step-files-btn-#{open_event.id}") |> render_click()
    view |> element("#select-additional-#{open_event.id}") |> render_click()

    file =
      file_input(view, "#step-upload-form-#{open_event.id}", :document, [
        %{name: "notes.pdf", content: "x", type: "application/pdf"}
      ])

    render_upload(file, "notes.pdf")
    view |> form("#step-upload-form-#{open_event.id}", %{"picker_slot" => "additional"}) |> render_change()
    view |> element("#upload-additional-#{open_event.id}") |> render_click()

    assert has_element?(view, "#step-files-#{open_event.id}", "notes.pdf")

    obligation = Obligations.get_obligation!(manager, obligation.id)
    documents = Obligations.list_cycle_documents(obligation)
    assert Enum.any?(documents, &(is_nil(&1.document_slot) and &1.file["original"] == "notes.pdf"))
  end

  test "step files modal: voided other file shows in step voided area, downloadable", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF",
        obligation_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    event = hd(Obligations.list_events(obligation))
    {:ok, doc} = Obligations.add_document(manager, obligation, event, upload_fixture("n.pdf"), nil)
    {:ok, _} = Obligations.void_document(manager, obligation, doc, %{reason: "dup"})

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#step-files-btn-#{event.id}") |> render_click()

    assert has_element?(view, "#step-voided-#{event.id}", "n.pdf")
    assert has_element?(view, "#voided-doc-#{doc.id} a[href*='/documents/#{doc.id}']")
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus_web/live/obligation_live_test.exs -k "step files modal"`
Expected: FAIL — `#step-files-btn-...` not found.

- [ ] **Step 3: Create the Surface B component**

Create `lib/argus_web/components/obligation_step_files.ex`:

```elixir
defmodule ArgusWeb.ObligationStepFiles do
  @moduledoc """
  Per-step supporting (non-required) files: this event's live "other" files and a
  voided-other area, plus an additional-file uploader when the step is uploadable.
  """
  use Phoenix.Component

  import ArgusWeb.CoreComponents

  alias Argus.Obligations
  alias ArgusWeb.LiveUpload

  attr :event, :map, required: true
  attr :obligation, :map, required: true
  attr :current_scope, :map, required: true
  attr :entity_slug, :string, required: true
  attr :required_slots, :list, required: true
  attr :uploads, :map, required: true
  attr :upload_slot_target, :any, default: nil
  attr :upload_slot_entries, :map, default: %{}
  attr :uploadable?, :boolean, required: true
  attr :voiding_document_id, :any, default: nil
  attr :void_reason_required?, :boolean, default: false
  attr :id_prefix, :string, default: ""

  def step_files(assigns) do
    {live_other, voided_other} =
      ArgusWeb.ObligationLive.DocumentHelpers.step_files(
        assigns.event.documents,
        assigns.required_slots
      )

    assigns =
      assigns
      |> assign(:live_other, live_other)
      |> assign(:voided_other, voided_other)
      |> assign(:form_id, "#{assigns.id_prefix}step-upload-form-#{assigns.event.id}")

    ~H"""
    <section id={"#{@id_prefix}step-files-#{@event.id}"} class="space-y-3">
      <div class="argus-meta-label">Supporting files</div>

      <p :if={@live_other == []} class="text-sm text-base-content/50">No supporting files on this step.</p>
      <ul :if={@live_other != []} class="divide-y divide-base-300 rounded-box border border-base-300">
        <li :for={doc <- @live_other} id={"#{@id_prefix}doc-row-#{doc.id}"} class="px-2.5 py-2 text-sm">
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
            <.icon name="hero-paper-clip-mini" class="size-3.5 text-base-content/40 shrink-0" />
            <.link
              href={"/entities/#{@entity_slug}/obligations/#{@obligation.id}/documents/#{doc.id}"}
              target="_blank"
              class="link link-hover truncate max-w-[12rem]"
            >
              {file_name(doc)}
            </.link>
            <span class="text-xs text-base-content/50">{format_datetime(doc.inserted_at)}</span>
            <div class="ml-auto flex items-center gap-1">
              <button
                :if={Obligations.document_deletable?(@current_scope, @obligation, doc)}
                id={"#{@id_prefix}delete-doc-#{doc.id}"}
                type="button"
                phx-click="delete_document"
                phx-value-document_id={doc.id}
                phx-value-event_id={@event.id}
                class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 text-error"
              >
                Delete
              </button>
              <button
                :if={
                  @voiding_document_id != doc.id &&
                    Obligations.document_voidable?(@current_scope, @obligation, doc)
                }
                id={"#{@id_prefix}void-doc-#{doc.id}"}
                type="button"
                phx-click="void_document"
                phx-value-document_id={doc.id}
                class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 text-error"
              >
                Void
              </button>
            </div>
          </div>
          <.void_form
            :if={@voiding_document_id == doc.id}
            doc={doc}
            event_id={@event.id}
            void_reason_required?={@void_reason_required?}
            id_prefix={@id_prefix}
          />
        </li>
      </ul>

      <section :if={@voided_other != []} id={"#{@id_prefix}step-voided-#{@event.id}"} class="space-y-1">
        <div class="argus-meta-label">Voided files</div>
        <ul class="divide-y divide-base-300 rounded-box border border-base-300">
          <li :for={doc <- @voided_other} id={"#{@id_prefix}voided-doc-#{doc.id}"} class="px-2.5 py-2 text-sm">
            <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
              <.icon name="hero-paper-clip-mini" class="size-3.5 text-base-content/40 shrink-0" />
              <.link
                href={"/entities/#{@entity_slug}/obligations/#{@obligation.id}/documents/#{doc.id}"}
                target="_blank"
                class="link link-hover truncate max-w-[12rem] line-through text-base-content/40"
              >
                {file_name(doc)}
              </.link>
              <span class="badge badge-xs badge-error">voided</span>
              <span class="text-xs text-base-content/50">{format_datetime(doc.inserted_at)}</span>
            </div>
            <p :if={doc.void_reason} class="text-xs text-base-content/50 mt-1 pl-5">
              Void reason: {doc.void_reason}
            </p>
          </li>
        </ul>
      </section>

      <div :if={@uploadable?} class="rounded-box border border-dashed border-base-300 p-2.5">
        <span class="text-sm text-base-content/70">Additional file</span>
        <.additional_uploader
          event={@event}
          id_prefix={@id_prefix}
          pending_entry={LiveUpload.entry_for_slot(@uploads, @upload_slot_entries, "additional")}
        />
      </div>

      <.form
        :if={@uploadable?}
        for={%{}}
        id={@form_id}
        data-upload-form
        phx-change="validate_upload"
        phx-submit="add_document"
        class="sr-only"
      >
        <input type="hidden" name="event_id" value={@event.id} />
        <input type="hidden" name="slot" value="additional" />
        <input type="hidden" name="picker_slot" value={picker_value(@upload_slot_target)} />
        <input type="hidden" name="document_slot" value="" disabled />
        <.live_file_input upload={@uploads.document} class="sr-only" />
      </.form>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".StepFilePicker">
        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              const panel = this.el.closest("section")
              const form = panel?.querySelector("[data-upload-form]")
              if (!form) return
              const pickerInput = form.querySelector("[name='picker_slot']")
              if (pickerInput) pickerInput.value = "additional"
              const fileInput = form.querySelector("input[type='file']")
              if (fileInput) fileInput.click()
            })
          }
        }
      </script>
    </section>
    """
  end

  attr :event, :map, required: true
  attr :id_prefix, :string, required: true
  attr :pending_entry, :any, default: nil

  defp additional_uploader(assigns) do
    assigns = assign(assigns, :ready?, LiveUpload.entry_ready?(assigns.pending_entry))

    ~H"""
    <div class="mt-2 flex flex-wrap items-center gap-2 border-t border-base-300/80 pt-2">
      <%= if @pending_entry do %>
        <span class="text-sm font-medium truncate min-w-0 flex-1">{@pending_entry.client_name}</span>
        <button
          id={"#{@id_prefix}upload-additional-#{@event.id}"}
          type="button"
          phx-click="add_document"
          phx-value-event_id={@event.id}
          phx-value-slot="additional"
          disabled={not @ready?}
          class={["btn btn-primary btn-xs h-7 min-h-7 shrink-0", not @ready? && "btn-disabled"]}
          phx-disable-with="Saving…"
        >
          Upload
        </button>
        <button type="button" phx-click="clear_upload_slot" phx-value-slot="additional" class="btn btn-ghost btn-xs h-7 min-h-7 shrink-0">
          Cancel
        </button>
      <% else %>
        <button
          id={"#{@id_prefix}select-additional-#{@event.id}"}
          type="button"
          phx-hook=".StepFilePicker"
          data-slot="additional"
          phx-click="select_upload_slot"
          phx-value-slot="additional"
          class="btn btn-outline btn-xs h-7 min-h-7 ml-auto"
        >
          Choose file
        </button>
      <% end %>
    </div>
    """
  end

  attr :doc, :map, required: true
  attr :event_id, :string, required: true
  attr :void_reason_required?, :boolean, required: true
  attr :id_prefix, :string, required: true

  defp void_form(assigns) do
    ~H"""
    <.form for={%{}} id={"#{@id_prefix}void-form-#{@doc.id}"} phx-submit="confirm_void_document" class="mt-2 pl-5 space-y-2">
      <input type="hidden" name="document_id" value={@doc.id} />
      <input type="hidden" name="event_id" value={@event_id} />
      <.input :if={@void_reason_required?} name="reason" type="text" label="Reason for voiding" required />
      <div class="flex flex-wrap gap-2">
        <.button class="btn btn-error btn-xs" phx-disable-with="Voiding…">Confirm void</.button>
        <button type="button" class="btn btn-ghost btn-xs" phx-click="cancel_void_document">Cancel</button>
      </div>
    </.form>
    """
  end

  defp picker_value(slot) when is_binary(slot), do: slot
  defp picker_value(_), do: ""

  defp file_name(%{file: file}) when is_map(file) do
    Map.get(file, "original") || Map.get(file, :original) || "file"
  end
end
```

- [ ] **Step 4: Wire Surface B into the desktop LiveView**

In `lib/argus_web/live/obligation_live/show.ex`:

(a) Add import:
```elixir
  import ArgusWeb.ObligationStepFiles
```

(b) Replace the timeline "Docs" button (`:171-180`) with a Files button keyed to the event:
```elixir
                <button
                  id={"step-files-btn-#{event.id}"}
                  type="button"
                  phx-click="open_step_files"
                  phx-value-event_id={event.id}
                  class="btn btn-ghost btn-xs h-6 min-h-6 px-1.5 gap-1 ml-auto"
                >
                  <.icon name="hero-paper-clip-mini" class="size-3.5" />
                  Files ({length(other_file_count(event, @doc_slots))})
                </button>
```
Add the helper near `cycle_documents/1`:
```elixir
  defp other_file_count(event, required_slots) do
    {live_other, _voided} = DocumentHelpers.step_files(event.documents, required_slots)
    live_other
  end
```

(c) Add the step-files modal next to the completion modal:
```elixir
      <div :if={@step_files_modal_event} id={"step-files-modal-#{@step_files_modal_event.id}"} class="modal modal-open">
        <div class="modal-box max-w-lg">
          <h3 class="font-bold text-lg">Files — {humanize_status(@step_files_modal_event.status)}</h3>
          <div class="mt-3">
            <.step_files
              event={@step_files_modal_event}
              obligation={@obligation}
              current_scope={@current_scope}
              entity_slug={@current_scope.entity.slug}
              required_slots={@doc_slots}
              uploads={@uploads}
              upload_slot_target={@upload_slot_target}
              upload_slot_entries={@upload_slot_entries}
              uploadable?={event_uploadable?(@step_files_modal_event, assigns)}
              voiding_document_id={@voiding_document_id}
              void_reason_required?={@void_reason_required?}
            />
          </div>
          <div class="modal-action mt-2">
            <button type="button" class="btn" phx-click="close_step_files">Close</button>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button type="button" phx-click="close_step_files">close</button>
        </form>
      </div>
```

(d) In `mount`, add the assign alongside `show_completion_modal`:
```elixir
     |> assign(:step_files_modal_event_id, nil)
     |> assign(:step_files_modal_event, nil)
```

(e) Add handlers (place near the completion modal handlers):
```elixir
  def handle_event("open_step_files", %{"event_id" => event_id}, socket) do
    case find_event(socket.assigns.obligation.events, event_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Step not found.")}

      event ->
        {:noreply,
         socket
         |> assign(:step_files_modal_event_id, event.id)
         |> assign(:step_files_modal_event, event)
         |> assign(:upload_slot_target, nil)}
    end
  end

  def handle_event("close_step_files", _params, socket) do
    {:noreply,
     socket
     |> assign(:step_files_modal_event_id, nil)
     |> assign(:step_files_modal_event, nil)
     |> assign(:upload_slot_target, nil)
     |> ArgusWeb.LiveUpload.clear_all_slot_entries()
     |> assign(:voiding_document_id, nil)}
  end
```

(f) Update `reload/1` so an open step-files modal refreshes its event after an action. Replace `reload/1` with:
```elixir
  defp reload(socket) do
    scope = socket.assigns.current_scope
    obligation = Obligations.get_obligation!(scope, socket.assigns.obligation.id)

    socket = assign_obligation(socket, obligation)

    case socket.assigns.step_files_modal_event_id do
      nil ->
        socket

      event_id ->
        assign(socket, :step_files_modal_event, find_event(obligation.events, event_id))
    end
  end
```
(`assign_obligation/2` already reassigns `@obligation`.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/argus_web/live/obligation_live_test.exs -k "step files modal"`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/argus_web/components/obligation_step_files.ex lib/argus_web/live/obligation_live/show.ex test/argus_web/live/obligation_live_test.exs
git commit -m "feat: per-step Step Files surface (desktop)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Type-slot-change reclassification (integration test)

**Files:**
- Test: `test/argus_web/live/obligation_live_test.exs`

**Interfaces:**
- Consumes: `Argus.Obligations.update_type/3` (existing propagation), the Surface A/B wiring from Tasks 3–4.

This task adds no production code — it verifies the spec's reclassification requirement holds end-to-end with the new surfaces. If it fails, the bug is in the surfaces' classification consumption (fix there).

- [ ] **Step 1: Write the test**

Add to `test/argus_web/live/obligation_live_test.exs`:

```elixir
  test "removing a required slot reclassifies a live obligation's file as supporting", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF",
        obligation_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    event = hd(Obligations.list_events(obligation))
    {:ok, _doc} = Obligations.add_document(manager, obligation, event, upload_fixture("r.pdf"), "receipt")

    # Admin drops the "receipt" slot from the type.
    {:ok, _type} = Obligations.update_type(manager, type, %{complete_documents: "form"})

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}")

    obligation = Obligations.get_obligation!(manager, obligation.id)
    [open_event] = Enum.filter(obligation.events, &(&1.status == "open"))

    # Completion view: receipt gone, "form" now required and unsatisfied; r.pdf not in slot rows.
    view |> element("#open-completion-modal") |> render_click()
    assert has_element?(view, "#completion-slot-form")
    refute has_element?(view, "#completion-slot-receipt")
    refute has_element?(view, "#completion-docs", "r.pdf")
    view |> element("#close-completion-modal") |> render_click()

    # Step files: r.pdf now a supporting file on its step.
    view |> element("#step-files-btn-#{open_event.id}") |> render_click()
    assert has_element?(view, "#step-files-#{open_event.id}", "r.pdf")
  end
```
Note: `#close-completion-modal` is the modal's Close button — add `id="close-completion-modal"` to that button in `show.ex` if not already present.

- [ ] **Step 2: Run the test**

Run: `mix test test/argus_web/live/obligation_live_test.exs -k "reclassifies"`
Expected: PASS. If `#close-completion-modal` isn't found, add the id to the Close button and re-run.

- [ ] **Step 3: Commit**

```bash
git add test/argus_web/live/obligation_live_test.exs lib/argus_web/live/obligation_live/show.ex
git commit -m "test: type slot removal reclassifies live file as supporting

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Mobile wiring (Surfaces A + B)

**Files:**
- Modify: `lib/argus_web/live/mobile_live/obligation_show.ex`
- Test: `test/argus_web/live/mobile_live_test.exs`

**Interfaces:**
- Consumes: both new components with `id_prefix="m-"`; the same events as desktop (the mobile LiveView already defines parallel handlers for `validate_upload`, `clear_upload_slot`, `delete_document`, `void_document`, `confirm_void_document`, `cancel_void_document`).
- Produces: mobile-prefixed ids (`m-open-completion-modal`, `m-step-files-btn-#{id}`, `m-select-slot-#{slot}`, `m-completion-upload-form`, `m-step-upload-form-#{id}`, etc.).

- [ ] **Step 1: Write the failing test**

Inspect the mobile test file header (`sed -n '1,20p' test/argus_web/live/mobile_live_test.exs`) for its login/fixture helpers and the mobile route prefix (`/m/:entity_slug/...`). Add:

```elixir
  test "mobile completion modal uploads into a slot", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)
    type = type_fixture(manager.entity, complete_documents: "receipt")

    {:ok, obligation} =
      Obligations.create_obligation(manager, %{
        title: "EPF",
        obligation_type_id: type.id,
        due_by: ~D[2026-06-30],
        open_note: "open"
      })

    {:ok, view, _html} =
      live(conn, ~p"/m/#{manager.entity.slug}/obligations/#{obligation.id}")

    view |> element("#m-open-completion-modal") |> render_click()
    view |> element("#m-select-slot-receipt") |> render_click()

    file =
      file_input(view, "#m-completion-upload-form", :document, [
        %{name: "receipt.pdf", content: "x", type: "application/pdf"}
      ])

    render_upload(file, "receipt.pdf")
    view |> form("#m-completion-upload-form", %{"picker_slot" => "receipt"}) |> render_change()
    view |> element("#m-upload-slot-receipt") |> render_click()

    assert has_element?(view, "#m-completion-slot-receipt", "receipt.pdf")
  end
```
(Adapt `Obligations` alias / imports to the mobile test file's existing ones.)

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/argus_web/live/mobile_live_test.exs -k "mobile completion modal"`
Expected: FAIL — `#m-open-completion-modal` not found.

- [ ] **Step 3: Apply the desktop changes to the mobile LiveView**

Mirror Task 3 Steps 4–5 and Task 4 Step 4 in `lib/argus_web/live/mobile_live/obligation_show.ex`, with `id_prefix="m-"` passed to both components and `m-` prepended to the modal/button ids. Concretely:
- Add `import ArgusWeb.ObligationCompletionDocuments` and `import ArgusWeb.ObligationStepFiles`.
- Replace the existing per-event documents modal/button with a `m-open-completion-modal` button + `<.completion_documents id_prefix="m-" ...>` modal, and `m-step-files-btn-#{event.id}` buttons + `<.step_files id_prefix="m-" ...>` modal.
- Replace mount assigns `documents_modal_event_id/documents_modal_event` with `show_completion_modal` (false) and `step_files_modal_event_id/step_files_modal_event` (nil).
- Replace `open_documents_modal`/`close_documents_modal` with `open_completion_modal`/`close_completion_modal` and add `open_step_files`/`close_step_files` (same bodies as desktop).
- Replace `select_upload_slot` with the slot-only version; replace `add_document` with the event-resolving version (same as desktop Task 3 Step 5d, using `DocumentHelpers.upload_event`); update `reload/1` to refresh `step_files_modal_event`.
- Update `open_documents_from_done` (mobile has one near `:594`) to set `show_completion_modal: true`.
- Add `cycle_documents/1`, `other_file_count/2` private helpers.

Use the desktop `show.ex` (post Tasks 3–4) as the reference implementation for exact handler bodies; the only differences are the `m-` id prefix on rendered elements and the mobile layout wrapper.

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/argus_web/live/mobile_live_test.exs -k "mobile completion modal"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/argus_web/live/mobile_live/obligation_show.ex test/argus_web/live/mobile_live_test.exs
git commit -m "feat: unified Documents surfaces (mobile)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Delete old components, migrate tests, full precommit

**Files:**
- Delete: `lib/argus_web/components/obligation_document_upload.ex`, `lib/argus_web/components/obligation_document_list.ex`
- Modify: `lib/argus_web/live/obligation_live/show.ex`, `lib/argus_web/live/mobile_live/obligation_show.ex` (remove now-dead imports/handlers/assigns/helpers)
- Modify: `test/argus_web/live/obligation_live_test.exs`, `test/argus_web/live/mobile_live_test.exs` (migrate tests still using old ids)

**Interfaces:**
- Consumes: nothing new.
- Produces: a green `mix precommit` with no references to the deleted modules.

- [ ] **Step 1: Remove old component imports/usages and dead LiveView code**

In both LiveViews, remove `import ArgusWeb.ObligationDocumentUpload` / `import ArgusWeb.ObligationDocumentList` if present, and delete any handlers/assigns no longer referenced: the old `documents_modal_event_id`/`documents_modal_event` assigns and any `reopen_documents_modal/2`, `find_event_document/3` usages that are now unused. Verify with:
```bash
grep -rn "ObligationDocumentUpload\|ObligationDocumentList\|documents_modal_event\|reopen_documents_modal\|open_documents_modal\|close_documents_modal" lib/
```
Expected after edits: no matches (or only definitions you then remove).

- [ ] **Step 2: Delete the old components**

```bash
git rm lib/argus_web/components/obligation_document_upload.ex lib/argus_web/components/obligation_document_list.ex
```

- [ ] **Step 3: Compile and fix references**

Run: `mix compile --warnings-as-errors`
Expected: clean. Fix any "undefined function" / "unused" errors by removing the dead code they point to.

- [ ] **Step 4: Migrate remaining tests using old ids**

Find tests still referencing removed ids/handlers:
```bash
grep -rn "documents-btn-\|document-form-\|#document-list-\|slot-upload-\|create-document-form\|open_documents_modal\|#doc-row-\|select-additional-\|upload-slot-" test/
```
For each remaining occurrence in `obligation_live_test.exs` / `mobile_live_test.exs` that exercises the old per-event modal upload flow, rewrite it to the new flow: open the completion modal (`#open-completion-modal`) for required-slot uploads, or the step-files modal (`#step-files-btn-#{event.id}`) for additional uploads, using the ids from Tasks 3–4. Delete duplicates that now overlap with the Task 3/4 tests.

- [ ] **Step 5: Run the full suite + precommit**

Run: `mix precommit`
Expected: PASS, 0 failures, no warnings.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: remove old Documents components; migrate tests to unified surfaces

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review notes

- **Spec coverage:** Surface A → Task 3; Surface B → Task 4; voided downloadable → Task 2 (+ asserted in Tasks 3/4); classification (incl. stale slot) → Task 1 (+ Task 5); type-change frozen/propagated behavior → Task 5 (relies on existing `propagate_complete_documents_to_live`, unchanged); one cycle button + per-step buttons → Tasks 3/4; mobile → Task 6; delete old components → Task 7.
- **Upload-config sharing:** only one modal is open at a time, so the single `:document` config is never contended; both surfaces' hidden forms use `data-upload-form` + their own colocated picker hook.
- **`add_document` unification:** Surface A omits `event_id` (resolves via `DocumentHelpers.upload_event/1`, document_slot = the slot); Surface B sends `event_id` + `slot: "additional"` (document_slot = nil). Single handler covers both (Task 3 Step 5d).
- **Kept:** `@doc_slots`/`@required_docs` (done checklist), `event_uploadable?/2` (Surface B), `LiveUpload`/`UploadValidate`, `propagate_complete_documents_to_live/3`.
