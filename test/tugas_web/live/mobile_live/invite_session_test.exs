defmodule TugasWeb.MobileLive.InviteSessionTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tugas.AccountsFixtures
  import Tugas.EntitiesFixtures

  alias Tugas.Entities

  defp mobile_conn(conn) do
    conn |> Plug.Test.put_req_cookie("tugas_view", "mobile")
  end

  test "admin sees QR SVG and roster heading", %{conn: conn} do
    scope = entity_scope_fixture()

    {:ok, lv, html} =
      conn
      |> mobile_conn()
      |> log_in_user(scope.user)
      |> live(~p"/m/#{scope.entity.slug}/invite-session/member")

    assert html =~ ~s(width="240.0")
    assert has_element?(lv, "#invite-qr svg")
    assert html =~ "Joined so far"
  end

  test "member is redirected to mobile dashboard", %{conn: conn} do
    member = member_scope_fixture()

    assert {:error, {:live_redirect, %{to: path}}} =
             conn
             |> mobile_conn()
             |> log_in_user(member.user)
             |> live(~p"/m/#{member.entity.slug}/invite-session/member")

    assert path == ~p"/m/#{member.entity.slug}"
  end

  test "close button closes the session", %{conn: conn} do
    scope = entity_scope_fixture()

    {:ok, lv, _html} =
      conn
      |> mobile_conn()
      |> log_in_user(scope.user)
      |> live(~p"/m/#{scope.entity.slug}/invite-session/member")

    html = lv |> element("button[phx-click='close']") |> render_click()
    assert html =~ "Session closed"
  end

  test "member_joined PubSub message inserts into roster", %{conn: conn} do
    scope = entity_scope_fixture()

    {:ok, lv, _html} =
      conn
      |> mobile_conn()
      |> log_in_user(scope.user)
      |> live(~p"/m/#{scope.entity.slug}/invite-session/member")

    joiner = username_user_fixture(%{username: "scannerjoe"})
    inv = Tugas.Repo.get_by!(Entities.Invitation, entity_id: scope.entity.id, reusable: true)
    {:ok, membership} = Entities.accept_invitation(joiner, inv.token)
    membership = Tugas.Repo.preload(membership, :user)
    send(lv.pid, {:member_joined, membership})

    html = render(lv)
    assert html =~ "scannerjoe"
  end
end
