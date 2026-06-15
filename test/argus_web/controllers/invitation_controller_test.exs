defmodule ArgusWeb.InvitationControllerTest do
  use ArgusWeb.ConnCase, async: true

  import Argus.AccountsFixtures

  alias Argus.Accounts
  alias Argus.Entities
  alias Argus.Entities.Invitation

  defp pending_invitation(email \\ nil) do
    admin = Argus.EntitiesFixtures.entity_scope_fixture()
    {:ok, invitation} = Entities.invite_member(admin, email, "member")
    %{admin: admin, invitation: invitation, encoded: Invitation.encode_token(invitation.token)}
  end

  test "create-account path registers, confirms, joins, logs in, redirects", %{conn: conn} do
    %{admin: admin, encoded: encoded} = pending_invitation()

    conn =
      post(conn, ~p"/invitations/#{encoded}/accept", %{
        "create" => %{"username" => "brandnew", "password" => "supersecret12"}
      })

    assert redirected_to(conn) == ~p"/entities/#{admin.entity.slug}"
    assert get_session(conn, :user_token)

    user = Accounts.get_user_by_username("brandnew")
    assert user.confirmed_at
    assert Entities.get_membership!(user, admin.entity).role == "member"
  end

  test "log-in-to-accept path joins an existing account", %{conn: conn} do
    existing = username_user_fixture(%{username: "returner"})
    %{admin: admin, encoded: encoded} = pending_invitation()

    conn =
      post(conn, ~p"/invitations/#{encoded}/accept", %{
        "login" => %{"identifier" => "returner", "password" => valid_user_password()}
      })

    assert redirected_to(conn) == ~p"/entities/#{admin.entity.slug}"
    assert get_session(conn, :user_token)
    assert Entities.get_membership!(existing, admin.entity).role == "member"
  end

  test "already-logged-in user joins with one click", %{conn: conn} do
    user = username_user_fixture(%{username: "alreadyin"})
    %{admin: admin, encoded: encoded} = pending_invitation()

    conn =
      conn
      |> log_in_user(user)
      |> post(~p"/invitations/#{encoded}/accept", %{})

    assert redirected_to(conn) == ~p"/entities/#{admin.entity.slug}"
    assert Entities.get_membership!(user, admin.entity).role == "member"
  end

  test "wrong login credentials redirect back to the invite", %{conn: conn} do
    username_user_fixture(%{username: "returner2"})
    %{encoded: encoded} = pending_invitation()

    conn =
      post(conn, ~p"/invitations/#{encoded}/accept", %{
        "login" => %{"identifier" => "returner2", "password" => "wrong password here"}
      })

    assert redirected_to(conn) == ~p"/invitations/#{encoded}"
    refute get_session(conn, :user_token)
  end

  test "an invalid token redirects home without a session", %{conn: conn} do
    conn = post(conn, ~p"/invitations/garbage/accept", %{})
    assert redirected_to(conn) == ~p"/"
    refute get_session(conn, :user_token)
  end
end
