defmodule ArgusWeb.DocumentControllerTest do
  use ArgusWeb.ConnCase, async: true

  alias Argus.Entities
  alias Argus.Obligations

  import Argus.EntitiesFixtures
  import Argus.ObligationsFixtures

  setup :register_and_log_in_user

  test "serves document when user is a member of the entity", %{conn: conn, user: user} do
    manager = manager_scope_fixture()

    %Entities.Membership{
      user_id: user.id,
      entity_id: manager.entity.id,
      role: "member",
      accepted_at: DateTime.utc_now(:second)
    }
    |> Entities.Membership.changeset(%{})
    |> Argus.Repo.insert!()

    {_, obligation} = obligation_fixture(manager)
    event = hd(Obligations.list_events(obligation))

    path = Path.join(System.tmp_dir!(), "serve_test_#{System.unique_integer()}.txt")
    File.write!(path, "file contents")

    upload = %Plug.Upload{
      path: path,
      filename: "serve_test.txt",
      content_type: "text/plain"
    }

    {:ok, document} =
      Obligations.add_document(manager, obligation, event, upload, nil)

    conn =
      get(
        conn,
        ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents/#{document.id}"
      )

    assert response(conn, 200)
  end

  test "serves a voided document so it can still be downloaded", %{conn: conn} do
    manager = manager_scope_fixture()
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

    path = Path.join(System.tmp_dir!(), "receipt_#{System.unique_integer()}.pdf")
    File.write!(path, "receipt contents")

    upload = %Plug.Upload{
      path: path,
      filename: "receipt.pdf",
      content_type: "application/pdf"
    }

    {:ok, document} =
      Obligations.add_document(manager, obligation, event, upload, "receipt")

    # Make it old enough to be voidable (past 48 hour window)
    old_document =
      document
      |> Ecto.Changeset.change(
        inserted_at: DateTime.add(DateTime.utc_now(:second), -49 * 3600, :second)
      )
      |> Argus.Repo.update!()

    # Void it (admin, with reason).
    {:ok, _} =
      Obligations.void_document(manager, obligation, old_document, %{reason: "wrong file"})

    conn =
      get(
        conn,
        ~p"/entities/#{manager.entity.slug}/obligations/#{obligation.id}/documents/#{old_document.id}"
      )

    assert response(conn, 200)
  end
end
