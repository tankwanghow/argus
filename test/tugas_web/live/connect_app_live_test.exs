defmodule TugasWeb.ConnectAppLiveTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tugas.EntitiesFixtures
  alias Tugas.Accounts

  setup %{conn: conn} do
    scope = entity_scope_fixture()
    # log_in_user stamps a fresh session token, so the user is in sudo mode
    conn = log_in_user(conn, scope.user)
    %{conn: conn, scope: scope}
  end

  test "renders a QR + pairing code and supports regenerate", %{conn: conn, scope: scope} do
    {:ok, lv, html} = live(conn, ~p"/entities/#{scope.entity.slug}/connect-app")
    assert html =~ "Connect mobile app"
    assert has_element?(lv, "#pairing-qr")

    # regenerate mints a different code
    assert lv |> element("button", "Regenerate") |> render_click() =~ "Connect mobile app"
  end

  test "revoke removes a paired token", %{conn: conn, scope: scope} do
    {:ok, {_t, _e}} =
      Accounts.exchange_pairing_code(Accounts.create_pairing_code(scope.user, scope.entity))

    [row] = Accounts.list_api_tokens(scope.user)

    {:ok, lv, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/connect-app")
    lv |> element("button[phx-value-id='#{row.id}']") |> render_click()

    assert Accounts.list_api_tokens(scope.user) == []
  end
end
