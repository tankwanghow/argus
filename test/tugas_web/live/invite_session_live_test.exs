defmodule TugasWeb.InviteSessionLiveTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tugas.AccountsFixtures
  import Tugas.EntitiesFixtures

  alias Tugas.Entities

  test "admin opens a member session: sees QR and a live roster updates", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, html} = live(conn, ~p"/entities/#{scope.entity.slug}/invite-session/member")

    assert html =~ "<svg"
    assert html =~ "/invitations/"

    joiner = username_user_fixture(%{username: "scannerjoe"})
    inv = Tugas.Repo.get_by!(Entities.Invitation, entity_id: scope.entity.id, reusable: true)
    {:ok, _} = Entities.accept_invitation(joiner, inv.token)

    assert render(view) =~ "scannerjoe"
  end

  test "a non-admin cannot open a session", %{conn: conn} do
    member = member_scope_fixture()
    conn = log_in_user(conn, member.user)

    assert {:error, {:live_redirect, %{to: to}}} =
             live(conn, ~p"/entities/#{member.entity.slug}/invite-session/member")

    assert to == ~p"/entities/#{member.entity.slug}/members"
  end
end
