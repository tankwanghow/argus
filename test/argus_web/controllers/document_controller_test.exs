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
end
