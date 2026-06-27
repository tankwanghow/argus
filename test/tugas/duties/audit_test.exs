defmodule Tugas.Duties.AuditTest do
  use Tugas.DataCase, async: true

  alias Tugas.Duties

  import Tugas.DutiesFixtures

  describe "update_duty/3" do
    test "logs title change" do
      {scope, duty} = manager_duty_scope_fixture()
      assert {:ok, _updated} = Duties.update_duty(scope, duty, %{title: "New"})
      logs = Duties.list_audit_logs(duty)
      assert Enum.any?(logs, &(&1.field == "title"))
    end

    test "logs due_by and primary_assignee changes" do
      {scope, duty} = manager_duty_scope_fixture()
      new_assignee = member_fixture(scope.entity)

      assert {:ok, _} =
               Duties.update_duty(scope, duty, %{
                 due_by: ~D[2026-03-01],
                 primary_assignee_id: new_assignee.id
               })

      fields = Duties.list_audit_logs(duty) |> Enum.map(& &1.field)
      assert "due_by" in fields
      assert "primary_assignee" in fields
    end

    test "member cannot update duty fields" do
      {scope, duty} = assigned_member_scope_fixture()
      assert :not_authorise = Duties.update_duty(scope, duty, %{title: "X"})
    end

    test "lists corrections newest-first" do
      {scope, duty} = manager_duty_scope_fixture()

      assert {:ok, _} = Duties.update_duty(scope, duty, %{title: "First"})

      [%{inserted_at: first_at} | _] =
        Duties.list_audit_logs(duty)

      # Backdate the first correction so the second is unambiguously newer.
      Tugas.Repo.update_all(Tugas.Duties.AuditLog,
        set: [inserted_at: DateTime.add(first_at, -60, :second)]
      )

      assert {:ok, _} = Duties.update_duty(scope, duty, %{title: "Second"})

      logs = Duties.list_audit_logs(duty)
      assert hd(logs).new_value == "Second"
    end
  end

  describe "update_collaborators/3" do
    test "adds and removes, logging each change" do
      {scope, duty} = manager_duty_scope_fixture()
      collab = member_fixture(scope.entity)

      assert {:ok, _} = Duties.update_collaborators(scope, duty, [collab.id])
      assert {:ok, _} = Duties.update_collaborators(scope, duty, [])

      fields = Duties.list_audit_logs(duty) |> Enum.map(& &1.field)
      assert "collaborators" in fields
    end
  end

  describe "edit_note/3" do
    test "author can edit within 48 hours" do
      {scope, duty} = assigned_member_scope_fixture()
      {:ok, _} = Duties.start_progress(scope, duty, %{note: "Started"})
      event = Duties.latest_event(duty)

      assert {:ok, updated} = Duties.edit_note(scope, event, %{note: "Fixed typo"})
      assert updated.note == "Fixed typo"
      assert Enum.any?(Duties.list_audit_logs(duty), &(&1.field == "note"))
    end

    test "author cannot edit after 48 hours" do
      {scope, duty} = assigned_member_scope_fixture()
      event = hd(Duties.list_events(duty))

      old = DateTime.add(DateTime.utc_now(:second), -49, :hour)

      event
      |> Ecto.Changeset.change(inserted_at: old)
      |> Tugas.Repo.update!()

      assert {:error, :locked} = Duties.edit_note(scope, event, %{note: "Too late"})
    end

    test "manager can edit before done regardless of age" do
      {member_scope, duty} = assigned_member_scope_fixture()
      manager = manager_scope_fixture_on_entity(member_scope.entity)
      event = hd(Duties.list_events(duty))

      old = DateTime.add(DateTime.utc_now(:second), -72, :hour)

      event
      |> Ecto.Changeset.change(inserted_at: old)
      |> Tugas.Repo.update!()

      assert {:ok, updated} = Duties.edit_note(manager, event, %{note: "Manager fix"})
      assert updated.note == "Manager fix"
    end
  end
end
