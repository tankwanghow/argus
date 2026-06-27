defmodule TugasWeb.InvitationLiveTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tugas.AccountsFixtures

  alias Tugas.Entities
  alias Tugas.Entities.Invitation

  defp pending_invitation do
    admin = Tugas.EntitiesFixtures.entity_scope_fixture()
    {:ok, invitation} = Entities.invite_member(admin, nil, "member")
    %{admin: admin, encoded: Invitation.encode_token(invitation.token)}
  end

  test "invalid token shows a not-valid message", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/invitations/garbage")
    assert html =~ "not valid"
  end

  test "logged-out page shows entity, role, create and login forms with no side effects",
       %{conn: conn} do
    %{admin: admin, encoded: encoded} = pending_invitation()

    {:ok, view, html} = live(conn, ~p"/invitations/#{encoded}")

    assert html =~ admin.entity.name
    assert html =~ "member"
    assert has_element?(view, "form#create-form")
    assert has_element?(view, "form#login-form")

    # Viewing must not create anyone or any membership.
    assert Entities.list_entity_members(admin.entity) |> length() == 1
  end

  test "logged-in user sees a one-click accept form", %{conn: conn} do
    user = username_user_fixture()
    %{admin: admin, encoded: encoded} = pending_invitation()

    {:ok, view, html} = live(log_in_user(conn, user), ~p"/invitations/#{encoded}")

    assert html =~ admin.entity.name
    assert has_element?(view, "form#accept-form")
    refute has_element?(view, "form#create-form")
  end
end
