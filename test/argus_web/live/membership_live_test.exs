defmodule ArgusWeb.MembershipLiveTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.ObligationsFixtures

  alias Argus.Entities

  setup :register_and_log_in_user

  test "admin sees members and can invite", %{conn: conn} do
    admin = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, admin.user)
    _member = member_fixture(admin.entity)

    {:ok, view, _html} = live(conn, ~p"/entities/#{admin.entity.slug}/members")

    assert has_element?(view, "#members-list")
    assert has_element?(view, "#invite-form")

    view
    |> form("#invite-form", %{"invite" => %{"email" => "new@example.com", "role" => "member"}})
    |> render_submit()

    assert has_element?(view, "#pending-invitations", "new@example.com")
  end

  test "admin can change a member's role", %{conn: conn} do
    admin = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, admin.user)
    member = member_fixture(admin.entity)
    membership = Entities.get_membership!(member, admin.entity)

    {:ok, view, _html} = live(conn, ~p"/entities/#{admin.entity.slug}/members")

    view
    |> element("#member-#{membership.id} form")
    |> render_change(%{"membership_id" => membership.id, "role" => "manager"})

    assert Entities.get_membership!(member, admin.entity).role == "manager"
  end

  test "non-admin does not see management controls", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, view, _html} = live(conn, ~p"/entities/#{manager.entity.slug}/members")

    refute has_element?(view, "#invite-form")
  end
end
