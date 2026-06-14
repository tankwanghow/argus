defmodule Argus.Obligations.AuditTest do
  use Argus.DataCase, async: true

  alias Argus.Obligations

  import Argus.ObligationsFixtures

  describe "update_obligation/3" do
    test "logs title change" do
      {scope, obligation} = manager_obligation_scope_fixture()
      assert {:ok, _updated} = Obligations.update_obligation(scope, obligation, %{title: "New"})
      logs = Obligations.list_audit_logs(obligation)
      assert Enum.any?(logs, &(&1.field == "title"))
    end

    test "logs due_by and primary_assignee changes" do
      {scope, obligation} = manager_obligation_scope_fixture()
      new_assignee = member_fixture(scope.entity)

      assert {:ok, _} =
               Obligations.update_obligation(scope, obligation, %{
                 due_by: ~D[2026-03-01],
                 primary_assignee_id: new_assignee.id
               })

      fields = Obligations.list_audit_logs(obligation) |> Enum.map(& &1.field)
      assert "due_by" in fields
      assert "primary_assignee" in fields
    end

    test "member cannot update obligation fields" do
      {scope, obligation} = assigned_member_scope_fixture()
      assert :not_authorise = Obligations.update_obligation(scope, obligation, %{title: "X"})
    end
  end

  describe "update_collaborators/3" do
    test "adds and removes, logging each change" do
      {scope, obligation} = manager_obligation_scope_fixture()
      collab = member_fixture(scope.entity)

      assert {:ok, _} = Obligations.update_collaborators(scope, obligation, [collab.id])
      assert {:ok, _} = Obligations.update_collaborators(scope, obligation, [])

      fields = Obligations.list_audit_logs(obligation) |> Enum.map(& &1.field)
      assert "collaborators" in fields
    end
  end

  describe "edit_note/3" do
    test "author can edit within 48 hours" do
      {scope, obligation} = assigned_member_scope_fixture()
      {:ok, _} = Obligations.start_progress(scope, obligation, %{note: "Started"})
      event = Obligations.latest_event(obligation)

      assert {:ok, updated} = Obligations.edit_note(scope, event, %{note: "Fixed typo"})
      assert updated.note == "Fixed typo"
      assert Enum.any?(Obligations.list_audit_logs(obligation), &(&1.field == "note"))
    end

    test "author cannot edit after 48 hours" do
      {scope, obligation} = assigned_member_scope_fixture()
      event = hd(Obligations.list_events(obligation))

      old = DateTime.add(DateTime.utc_now(:second), -49, :hour)

      event
      |> Ecto.Changeset.change(inserted_at: old)
      |> Argus.Repo.update!()

      assert {:error, :locked} = Obligations.edit_note(scope, event, %{note: "Too late"})
    end

    test "manager can edit before done regardless of age" do
      {member_scope, obligation} = assigned_member_scope_fixture()
      manager = manager_scope_fixture_on_entity(member_scope.entity)
      event = hd(Obligations.list_events(obligation))

      old = DateTime.add(DateTime.utc_now(:second), -72, :hour)

      event
      |> Ecto.Changeset.change(inserted_at: old)
      |> Argus.Repo.update!()

      assert {:ok, updated} = Obligations.edit_note(manager, event, %{note: "Manager fix"})
      assert updated.note == "Manager fix"
    end
  end
end
