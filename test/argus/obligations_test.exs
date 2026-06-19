defmodule Argus.ObligationsTest do
  use Argus.DataCase, async: true

  alias Argus.Obligations

  import Argus.EntitiesFixtures, only: [manager_scope_fixture: 0, member_scope_fixture: 0]
  import Argus.ObligationsFixtures

  describe "create_obligation/2" do
    test "creates obligation, open event, snapshots type rules, and open note" do
      scope = manager_scope_fixture()

      type = type_fixture(scope.entity, complete_documents: "receipt")

      assignee = member_fixture(scope.entity)

      attrs = %{
        title: "EPF Jan",
        obligation_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-01-15],
        open_note: "Submit by 15th"
      }

      assert {:ok, obligation} = Obligations.create_obligation(scope, attrs)
      assert obligation.series_id
      assert obligation.status == "active"
      assert obligation.complete_documents == "receipt"

      events = Obligations.list_events(obligation)
      assert hd(events).status == "open"
      assert hd(events).note == "Submit by 15th"
    end

    test "returns :not_authorise for members" do
      scope = member_scope_fixture()
      type = type_fixture(scope.entity)
      assignee = member_fixture(scope.entity)

      attrs = %{
        title: "EPF Jan",
        obligation_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-01-15]
      }

      assert :not_authorise = Obligations.create_obligation(scope, attrs)
    end

    test "allows creating without a primary assignee" do
      scope = manager_scope_fixture()
      type = type_fixture(scope.entity)

      attrs = %{
        title: "Unassigned filing",
        obligation_type_id: type.id,
        primary_assignee_id: nil,
        due_by: ~D[2026-06-20],
        open_note: "Needs an owner"
      }

      assert {:ok, obligation} = Obligations.create_obligation(scope, attrs)
      assert is_nil(obligation.primary_assignee_id)
    end

    test "rejects a title longer than 30 characters" do
      scope = manager_scope_fixture()
      type = type_fixture(scope.entity)

      attrs = %{
        title: String.duplicate("x", 31),
        obligation_type_id: type.id,
        due_by: ~D[2026-01-15],
        open_note: "open"
      }

      assert {:error, changeset} = Obligations.create_obligation(scope, attrs)
      assert "should be at most 30 character(s)" in errors_on(changeset).title
    end

    test "requires an open note" do
      scope = manager_scope_fixture()
      type = type_fixture(scope.entity)
      assignee = member_fixture(scope.entity)

      attrs = %{
        title: "EPF Jan",
        obligation_type_id: type.id,
        primary_assignee_id: assignee.id,
        due_by: ~D[2026-01-15]
      }

      assert {:error, :note_required} = Obligations.create_obligation(scope, attrs)
    end
  end

  describe "completed-in-error schema" do
    test "new correction fields default to nil on a created obligation" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-30],
          open_note: "open"
        })

      assert obligation.completed_in_error_at == nil
      assert obligation.completed_in_error_by_id == nil
      assert obligation.completed_in_error_reason == nil
      assert obligation.replaces_id == nil
      assert obligation.replaced_by_id == nil
    end
  end

  describe "start_progress/3" do
    test "creates in_progress event with note" do
      {scope, obligation} = assigned_member_scope_fixture()

      assert {:ok, event} =
               Obligations.start_progress(scope, obligation, %{note: "Gathering documents"})

      assert event.status == "in_progress"
      assert event.note == "Gathering documents"
    end

    test "requires a progress note" do
      {scope, obligation} = assigned_member_scope_fixture()
      assert {:error, :note_required} = Obligations.start_progress(scope, obligation, %{})
    end

    test "is idempotent — rejected if already in_progress" do
      {scope, obligation} = assigned_member_scope_fixture()
      assert {:ok, _} = Obligations.start_progress(scope, obligation, %{note: "Started"})
      assert {:error, :not_open} = Obligations.start_progress(scope, obligation, %{note: "Again"})
    end
  end

  describe "complete/3" do
    test "marks done, stamps completed_at, and spawns next when recurring" do
      {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:ok, done_obligation, new_obligation} =
               Obligations.complete(scope, obligation, %{
                 note: "Filed on time",
                 next_due_by: ~D[2026-02-15]
               })

      assert done_obligation.completed_at
      done_event = Obligations.latest_event(done_obligation)
      assert done_event.status == "done"
      assert new_obligation.due_by == ~D[2026-02-15]
      assert new_obligation.series_id == obligation.series_id
    end

    test "spawned next cycle inherits the completed cycle's opening note" do
      {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:ok, _done, spawned} =
               Obligations.complete(scope, obligation, %{
                 note: "Filed on time",
                 next_due_by: ~D[2026-02-15]
               })

      open_event = Obligations.latest_event(spawned)
      assert open_event.status == "open"
      assert open_event.note == "Recurring task opened"
    end

    test "requires next_due_by for a recurring, not-ended series" do
      {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:error, :next_due_required} =
               Obligations.complete(scope, obligation, %{note: "Done"})
    end

    test "requires a completion note" do
      {scope, obligation} = assigned_member_scope_fixture()
      assert {:error, :note_required} = Obligations.complete(scope, obligation, %{})
    end

    test "is idempotent — a second Done on the same cycle is rejected" do
      {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")

      assert {:ok, done_obligation, _} =
               Obligations.complete(scope, obligation, %{
                 note: "Done",
                 next_due_by: ~D[2026-02-15]
               })

      assert {:error, :not_live} =
               Obligations.complete(scope, done_obligation, %{
                 note: "Again",
                 next_due_by: ~D[2026-03-15]
               })
    end
  end

  describe "cancel_obligation/3" do
    test "requires a cancel reason" do
      {scope, obligation} = manager_obligation_scope_fixture()
      assert {:error, :note_required} = Obligations.cancel_obligation(scope, obligation, %{})
    end

    test "sets status cancelled and logs event with reason" do
      {scope, obligation} = manager_obligation_scope_fixture()

      assert {:ok, cancelled} =
               Obligations.cancel_obligation(scope, obligation, %{note: "No longer applicable"})

      assert cancelled.status == "cancelled"
      event = Obligations.latest_event(cancelled)
      assert event.status == "cancelled"
      assert event.note == "No longer applicable"
    end
  end

  describe "skip_cycle/3" do
    test "requires a skip reason" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:error, :note_required} =
               Obligations.skip_cycle(scope, obligation, %{next_due_by: ~D[2026-02-15]})
    end

    test "requires next_due_by" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:error, :next_due_required} =
               Obligations.skip_cycle(scope, obligation, %{note: "Deferred"})
    end

    test "rejects one-off obligations" do
      {scope, obligation} = manager_obligation_scope_fixture()

      assert {:error, :not_recurring} =
               Obligations.skip_cycle(scope, obligation, %{
                 note: "Skip",
                 next_due_by: ~D[2026-07-15]
               })
    end

    test "cancels current cycle and spawns next without done validation" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:ok, cancelled, spawned} =
               Obligations.skip_cycle(scope, obligation, %{
                 note: "Deferred this month",
                 next_due_by: ~D[2026-02-15]
               })

      assert cancelled.status == "cancelled"
      refute cancelled.completed_at
      event = Obligations.latest_event(cancelled)
      assert event.status == "cancelled"
      assert event.note == "Deferred this month"
      assert spawned.due_by == ~D[2026-02-15]
      assert spawned.series_id == obligation.series_id
      assert spawned.status == "active"
    end

    test "is idempotent — a second skip on the same cycle is rejected" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:ok, cancelled, _} =
               Obligations.skip_cycle(scope, obligation, %{
                 note: "Skip",
                 next_due_by: ~D[2026-02-15]
               })

      assert {:error, :not_live} =
               Obligations.skip_cycle(scope, cancelled, %{
                 note: "Again",
                 next_due_by: ~D[2026-03-15]
               })
    end
  end

  describe "end_series/3" do
    test "requires a reason" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")
      assert {:error, :note_required} = Obligations.end_series(scope, obligation, %{})
    end

    test "cancels the current cycle so it can never be completed/spawn" do
      {scope, obligation} = recurring_manager_scope_fixture(interval: "monthly")

      assert {:ok, ended} =
               Obligations.end_series(scope, obligation, %{note: "Client left"})

      assert ended.status == "cancelled"
      assert ended.series_ended_at
      assert Obligations.latest_event(ended).note == "Client left"
      assert {:error, :not_live} = Obligations.complete(scope, ended, %{note: "Too late"})
    end
  end

  describe "Obligation.changeset/2" do
    alias Argus.Obligations.Obligation
    alias Argus.Repo

    test "translates one-live-cycle-per-series unique constraint" do
      {_scope, obligation} = recurring_primary_scope_fixture()

      duplicate =
        %Obligation{
          entity_id: obligation.entity_id,
          series_id: obligation.series_id,
          status: "active",
          complete_documents: ""
        }
        |> Obligation.changeset(%{
          title: "Racing successor",
          obligation_type_id: obligation.obligation_type_id,
          primary_assignee_id: obligation.primary_assignee_id,
          due_by: ~D[2026-07-15]
        })

      assert {:error, changeset} = Repo.insert(duplicate)

      assert {:series_id, {_msg, opts}} =
               Enum.find(changeset.errors, fn {field, _} -> field == :series_id end)

      assert opts[:constraint] == :unique
      assert opts[:constraint_name] == "obligations_one_live_cycle_per_series"
    end
  end

  describe "list_obligations/2" do
    test "filters by status and query" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)

      {:ok, live_obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF Live",
          obligation_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-06-30],
          open_note: "Live"
        })

      {:ok, completed} =
        Obligations.create_obligation(manager, %{
          title: "EPF Done",
          obligation_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-05-30],
          open_note: "Done cycle"
        })

      assert {:ok, completed, _} =
               Obligations.complete(member_scope, completed, %{
                 note: "Completed",
                 next_due_by: nil
               })

      {:ok, cancelled} =
        Obligations.create_obligation(manager, %{
          title: "EPF Cancelled",
          obligation_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-04-30],
          open_note: "Cancel cycle"
        })

      assert {:ok, _} =
               Obligations.cancel_obligation(manager, cancelled, %{note: "Superseded"})

      live_ids = manager |> Obligations.list_obligations(status: :live) |> Enum.map(& &1.id)

      completed_ids =
        manager |> Obligations.list_obligations(status: :completed) |> Enum.map(& &1.id)

      cancelled_ids =
        manager |> Obligations.list_obligations(status: :cancelled) |> Enum.map(& &1.id)

      assert live_obligation.id in live_ids
      refute completed.id in live_ids
      assert completed.id in completed_ids
      assert cancelled.id in cancelled_ids

      assert [found] = Obligations.list_obligations(manager, status: :all, query: "done")
      assert found.id == completed.id

      {:ok, other_live} =
        Obligations.create_obligation(manager, %{
          title: "Other Live",
          obligation_type_id: type_fixture(manager.entity).id,
          primary_assignee_id: manager.user.id,
          due_by: ~D[2026-07-01],
          open_note: "Other"
        })

      my_live_ids =
        member_scope |> Obligations.list_obligations(status: :my_live) |> Enum.map(& &1.id)

      my_completed_ids =
        member_scope |> Obligations.list_obligations(status: :my_completed) |> Enum.map(& &1.id)

      assert live_obligation.id in my_live_ids
      refute other_live.id in my_live_ids
      assert completed.id in my_completed_ids
      refute completed.id in my_live_ids
    end
  end

  describe "list_unassigned/1 and list_recently_completed/1" do
    test "list_unassigned returns live obligations with no primary assignee" do
      manager = manager_scope_fixture()
      type = type_fixture(manager.entity)
      assignee = member_fixture(manager.entity)

      {:ok, unassigned} =
        Obligations.create_obligation(manager, %{
          title: "Needs owner",
          obligation_type_id: type.id,
          primary_assignee_id: nil,
          due_by: ~D[2026-06-20],
          open_note: "Unassigned"
        })

      {:ok, _assigned} =
        Obligations.create_obligation(manager, %{
          title: "Has owner",
          obligation_type_id: type.id,
          primary_assignee_id: assignee.id,
          due_by: ~D[2026-06-21],
          open_note: "Assigned"
        })

      ids = manager |> Obligations.list_unassigned() |> Enum.map(& &1.id)
      assert unassigned.id in ids
      assert length(ids) == 1
    end

    test "list_recently_completed returns obligations completed within 14 days" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, recent} =
        Obligations.create_obligation(manager, %{
          title: "Just done",
          obligation_type_id: type.id,
          primary_assignee_id: member_scope.user.id,
          due_by: ~D[2026-06-01],
          open_note: "Recent"
        })

      assert {:ok, _, _} =
               Obligations.complete(member_scope, recent, %{note: "Done", next_due_by: nil})

      ids = manager |> Obligations.list_recently_completed() |> Enum.map(& &1.id)
      assert recent.id in ids
    end

    test "my_live excludes unassigned obligations for members" do
      manager = manager_scope_fixture()
      member_scope = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, unassigned} =
        Obligations.create_obligation(manager, %{
          title: "Nobody assigned",
          obligation_type_id: type.id,
          primary_assignee_id: nil,
          due_by: ~D[2026-06-20],
          open_note: "Nobody"
        })

      my_live_ids =
        member_scope |> Obligations.list_obligations(status: :my_live) |> Enum.map(& &1.id)

      refute unassigned.id in my_live_ids
    end
  end

  describe "event_summaries_for/1" do
    test "returns event count and latest event with status_by" do
      {scope, obligation} = assigned_member_scope_fixture()

      assert {:ok, _} =
               Obligations.start_progress(scope, obligation, %{note: "Working on it"})

      summaries = Obligations.event_summaries_for([obligation])
      summary = Map.fetch!(summaries, obligation.id)

      assert summary.event_count == 2
      assert summary.latest_event.status == "in_progress"
      assert summary.latest_event.status_by.email == scope.user.email
    end
  end

  describe "live/1" do
    test "includes active incomplete obligations only" do
      {_scope, obligation} = obligation_fixture(manager_scope_fixture())

      assert [_] =
               Obligations.live()
               |> Argus.Repo.all()
               |> Enum.filter(&(&1.id == obligation.id))

      obligation
      |> Ecto.Changeset.change(completed_at: DateTime.utc_now(:second))
      |> Argus.Repo.update!()

      refute Enum.any?(Obligations.live() |> Argus.Repo.all(), &(&1.id == obligation.id))
    end
  end

  describe "mark_completed_in_error/3" do
    test "flags the done cycle and spawns a standalone one-off replacement" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      member = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF Jan",
          obligation_type_id: type.id,
          primary_assignee_id: member.user.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _spawned} = Obligations.complete(manager, obligation, %{note: "Done"})

      assert {:ok, original, replacement} =
               Obligations.mark_completed_in_error(manager, done, %{reason: "Wrong figures filed"})

      # original flagged, not mutated into a live cycle
      assert original.completed_in_error_at
      assert original.completed_in_error_by_id == manager.user.id
      assert original.completed_in_error_reason == "Wrong figures filed"
      assert original.replaced_by_id == replacement.id
      assert original.completed_at == done.completed_at

      # replacement is a fresh, live, standalone one-off
      assert replacement.series_id != original.series_id
      assert replacement.series_ended_at
      assert replacement.status == "active"
      assert replacement.completed_at == nil
      assert replacement.due_by == ~D[2026-06-15]
      assert replacement.title == "EPF Jan"
      assert replacement.primary_assignee_id == member.user.id
      assert replacement.replaces_id == original.id

      # open event carries the reason
      open_event = Obligations.latest_event(replacement)
      assert open_event.status == "open"
      assert open_event.note == "Wrong figures filed"

      # an audit row was written on the original
      assert Enum.any?(
               Obligations.list_audit_logs(original),
               &(&1.field == "completed_in_error" and &1.new_value == "Wrong figures filed")
             )
    end

    test "replacement_due_by overrides the inherited due date" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

      assert {:ok, _original, replacement} =
               Obligations.mark_completed_in_error(manager, done, %{
                 reason: "redo",
                 replacement_due_by: ~D[2026-07-01]
               })

      assert replacement.due_by == ~D[2026-07-01]
    end

    test "a blank replacement_due_by falls back to the original's due date" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

      # A cleared date field submits "" — must not crash; falls back to original due_by.
      assert {:ok, _original, replacement} =
               Obligations.mark_completed_in_error(manager, done, %{
                 reason: "redo",
                 replacement_due_by: ""
               })

      assert replacement.due_by == ~D[2026-06-15]
    end

    test "completing the one-off replacement does not require next_due and does not spawn" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      # recurring type — but the replacement must still behave as a one-off
      type = type_fixture(manager.entity, recurring_interval: "monthly")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _spawned} =
        Obligations.complete(manager, obligation, %{note: "Done", next_due_by: ~D[2026-07-15]})

      {:ok, _original, replacement} =
        Obligations.mark_completed_in_error(manager, done, %{reason: "redo"})

      # No next_due required, returns spawned == nil (series already ended on the replacement).
      assert {:ok, completed_replacement, nil} =
               Obligations.complete(manager, replacement, %{note: "Redone"})

      assert completed_replacement.completed_at
    end

    test "a recurring original's auto-spawned successor is untouched" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity, recurring_interval: "monthly")

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, spawned} =
        Obligations.complete(manager, obligation, %{note: "Done", next_due_by: ~D[2026-07-15]})

      {:ok, _original, replacement} =
        Obligations.mark_completed_in_error(manager, done, %{reason: "redo"})

      # The recurring successor still lives, still in the original series, unchanged.
      reloaded = Obligations.get_obligation!(manager, spawned.id)
      assert reloaded.completed_at == nil
      assert reloaded.status == "active"
      assert reloaded.series_id == done.series_id
      assert reloaded.replaces_id == nil

      # The replacement is in its own series, separate from the recurring chain.
      assert replacement.series_id != done.series_id
      assert spawned.id in Enum.map(Obligations.list_series(done.series_id), & &1.id)
      refute replacement.id in Enum.map(Obligations.list_series(done.series_id), & &1.id)
    end

    test "rejects a live (not completed) cycle" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      assert {:error, :not_correctable} =
               Obligations.mark_completed_in_error(manager, obligation, %{reason: "x"})
    end

    test "rejects a cancelled cycle" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, cancelled} = Obligations.cancel_obligation(manager, obligation, %{note: "drop"})

      assert {:error, :not_correctable} =
               Obligations.mark_completed_in_error(manager, cancelled, %{reason: "x"})
    end

    test "rejects double-correction" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

      {:ok, original, _replacement} =
        Obligations.mark_completed_in_error(manager, done, %{reason: "first"})

      assert {:error, :already_corrected} =
               Obligations.mark_completed_in_error(manager, original, %{reason: "second"})
    end

    test "requires a reason" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

      assert {:error, :note_required} =
               Obligations.mark_completed_in_error(manager, done, %{reason: ""})
    end

    test "members may not correct" do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      member = member_scope_on_entity(manager.entity)
      type = type_fixture(manager.entity)

      {:ok, obligation} =
        Obligations.create_obligation(manager, %{
          title: "EPF",
          obligation_type_id: type.id,
          primary_assignee_id: member.user.id,
          due_by: ~D[2026-06-15],
          open_note: "open"
        })

      {:ok, done, _} = Obligations.complete(manager, obligation, %{note: "Done"})

      assert :not_authorise =
               Obligations.mark_completed_in_error(member, done, %{reason: "x"})
    end
  end
end
