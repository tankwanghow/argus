defmodule ArgusWeb.MobileAuthTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.AccountsFixtures

  alias Argus.Accounts

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  describe "mobile registration" do
    test "renders under mobile_standalone shell", %{conn: conn} do
      conn = put_req_header(conn, "user-agent", @mobile_ua)
      {:ok, _lv, html} = live(conn, ~p"/m/users/register")

      assert html =~ "Register"
      assert html =~ "mobile_standalone" or html =~ "Argus"
      refute html =~ ~s|id="entity-nav"|
    end

    test "creates account and navigates to mobile log-in", %{conn: conn} do
      conn = put_req_header(conn, "user-agent", @mobile_ua)
      {:ok, lv, _html} = live(conn, ~p"/m/users/register")

      email = unique_user_email()

      {:ok, _lv, html} =
        lv
        |> form("#m-registration-form", user: valid_user_attributes(email: email))
        |> render_submit()
        |> follow_redirect(conn, ~p"/m/users/log-in")

      assert html =~ "An email was sent"
    end
  end

  describe "mobile login" do
    test "renders magic and password forms", %{conn: conn} do
      conn = put_req_header(conn, "user-agent", @mobile_ua)
      {:ok, view, html} = live(conn, ~p"/m/users/log-in")

      assert html =~ "Log in with email"
      assert has_element?(view, "#m-login-form-password")
    end

    test "password login redirects mobile user to mobile dashboard", %{conn: conn} do
      scope = Argus.EntitiesFixtures.entity_scope_fixture()
      user = set_password(scope.user)
      conn = put_req_header(conn, "user-agent", @mobile_ua)

      {:ok, lv, _html} = live(conn, ~p"/m/users/log-in")

      form =
        form(lv, "#m-login-form-password",
          user: %{identifier: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)
      assert redirected_to(conn) == ~p"/m/#{scope.entity.slug}"
    end
  end

  describe "mobile confirmation" do
    test "renders confirmation for unconfirmed user", %{conn: conn} do
      user = unconfirmed_user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      conn = put_req_header(conn, "user-agent", @mobile_ua)
      {:ok, _lv, html} = live(conn, ~p"/m/users/log-in/#{token}")

      assert html =~ "Confirm and stay logged in"
      assert html =~ "m-confirmation-form"
    end
  end
end
