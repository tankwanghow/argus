defmodule TugasWeb.MobileLive.DutyIndexTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tugas.DutiesFixtures

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  setup :register_and_log_in_user

  defp mobile_conn(conn, scope) do
    conn |> log_in_user(scope.user) |> put_req_header("user-agent", @mobile_ua)
  end

  test "duty list renders at /m/:slug/duties", %{conn: conn} do
    {scope, duty} = assigned_member_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/duties")

    assert has_element?(view, "#mobile-duties")
    assert has_element?(view, "#m-ob-#{duty.id}")
  end
end
