defmodule ArgusWeb.MobileAuthTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.AccountsFixtures

  alias Argus.Accounts

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  describe "unified auth UI" do
    test "register and log-in use mobile_standalone on desktop UA", %{conn: conn} do
      {:ok, _lv, register_html} = live(conn, ~p"/users/register")
      assert register_html =~ "Register"
      assert register_html =~ "Argus"
      refute register_html =~ ~s|id="entity-nav"|

      {:ok, view, login_html} = live(conn, ~p"/users/log-in")
      assert login_html =~ "Log in with email"
      refute login_html =~ ~s|id="entity-nav"|
      assert has_element?(view, "#login_form_password")
    end

    test "register and log-in use mobile_standalone on mobile UA", %{conn: conn} do
      conn = put_req_header(conn, "user-agent", @mobile_ua)

      {:ok, _lv, html} = live(conn, ~p"/users/register")
      assert html =~ "Register"
      refute html =~ ~s|id="entity-nav"|

      {:ok, view, html} = live(conn, ~p"/users/log-in")
      assert html =~ "Log in with email"
      assert has_element?(view, "#login_form_password")
    end

    test "registration creates account and navigates to log-in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()

      {:ok, _lv, html} =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email))
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "An email was sent"
    end

    test "desktop UA password login redirects to desktop dashboard", %{conn: conn} do
      scope = Argus.EntitiesFixtures.entity_scope_fixture()
      user = set_password(scope.user)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{identifier: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)
      assert redirected_to(conn) == ~p"/entities/#{scope.entity.slug}"
    end

    test "mobile UA password login redirects to mobile dashboard", %{conn: conn} do
      scope = Argus.EntitiesFixtures.entity_scope_fixture()
      user = set_password(scope.user)
      conn = put_req_header(conn, "user-agent", @mobile_ua)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{identifier: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)
      assert redirected_to(conn) == ~p"/m/#{scope.entity.slug}"
    end

    test "confirmation uses standalone shell", %{conn: conn} do
      user = unconfirmed_user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, _lv, html} = live(conn, ~p"/users/log-in/#{token}")
      assert html =~ "Confirm and stay logged in"
      assert html =~ "confirmation_form"
    end
  end
end
