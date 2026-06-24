defmodule ArgusWeb.EntityLiveSelectTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Argus.Entities

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  setup :register_and_log_in_user

  defp mobile_conn(conn, scope) do
    conn |> log_in_user(scope.user) |> put_req_header("user-agent", @mobile_ua)
  end

  test "user menu links to all entities picker", %{conn: conn} do
    scope = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, html} =
      live(conn, ~p"/entities/#{scope.entity.slug}")

    assert html =~ ~s|href="/entities?pick=1"|
    assert has_element?(view, "a[href='/entities?pick=1']", "All entities")
  end

  test "pick=1 shows entity picker when user has multiple entities", %{conn: conn} do
    scope = Argus.EntitiesFixtures.manager_scope_fixture()

    {:ok, _} =
      Entities.create_entity(scope, %{slug: "beta-corp", name: "Beta Corp"})

    conn = log_in_user(conn, scope.user)

    {:ok, _view, html} = live(conn, ~p"/entities?pick=1")
    assert html =~ "Your entities"
    assert html =~ "Beta Corp"
  end

  test "pick=1 shows picker even for a single entity", %{conn: conn} do
    scope = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, _view, html} = live(conn, ~p"/entities?pick=1")
    assert html =~ "Your entities"
    assert html =~ scope.entity.name
  end

  test "mobile UA picker uses mobile shell and href enter links", %{conn: conn} do
    scope = Argus.EntitiesFixtures.manager_scope_fixture()

    {:ok, other} =
      Entities.create_entity(scope, %{slug: "beta-corp", name: "Beta Corp"})

    conn = mobile_conn(conn, scope)

    {:ok, view, html} = live(conn, ~p"/entities?pick=1")

    assert html =~ "Your entities"
    assert html =~ "Beta Corp"
    assert has_element?(view, "a[href='/m/#{other.slug}']", "Enter")
  end

  test "admin can edit entity name and timezone from picker", %{conn: conn} do
    scope = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/entities?pick=1")

    assert has_element?(view, "#edit-entity-#{scope.entity.id}")

    view |> element("#edit-entity-#{scope.entity.id}") |> render_click()
    assert has_element?(view, "#edit-entity-form-#{scope.entity.id}")

    view
    |> form("#edit-entity-form-#{scope.entity.id}", %{
      "entity_id" => scope.entity.id,
      "edit_entity" => %{
        "name" => "Renamed Corp",
        "slug" => scope.entity.slug,
        "timezone" => "Asia/Singapore"
      }
    })
    |> render_submit()

    assert render(view) =~ "Renamed Corp"

    assert Entities.get_entity_by_slug_for_user!(scope.entity.slug, scope.user).timezone ==
             "Asia/Singapore"
  end

  test "member picker has no edit controls", %{conn: conn} do
    scope = Argus.EntitiesFixtures.member_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/entities?pick=1")

    refute has_element?(view, "[id^='edit-entity-']")
  end

  test "mobile admin can edit entity from picker", %{conn: conn} do
    scope = Argus.EntitiesFixtures.entity_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/entities?pick=1")

    view |> element("#edit-entity-#{scope.entity.id}") |> render_click()

    view
    |> form("#edit-entity-form-#{scope.entity.id}", %{
      "entity_id" => scope.entity.id,
      "edit_entity" => %{
        "name" => "Mobile Renamed",
        "slug" => scope.entity.slug,
        "timezone" => "UTC"
      }
    })
    |> render_submit()

    assert render(view) =~ "Mobile Renamed"
  end

  test "update_entity returns not_authorise for non-admin", %{conn: _conn} do
    member = Argus.EntitiesFixtures.member_scope_fixture()
    entity = member.entity

    assert :not_authorise =
             Entities.update_entity(member, entity, %{name: "Nope"})
  end

  test "mobile picker enter links go directly to mobile dashboard", %{conn: conn} do
    scope = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = mobile_conn(conn, scope)

    {:ok, view, _html} = live(conn, ~p"/entities?pick=1")

    assert has_element?(view, "a[href='/m/#{scope.entity.slug}']", "Enter")
    refute render(view) =~ ~s|href="/entities/#{scope.entity.slug}"|
  end

  test "desktop picker enter links use desktop dashboard paths", %{conn: conn} do
    scope = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/entities?pick=1")

    assert has_element?(view, "a[href='/entities/#{scope.entity.slug}']", "Enter")
    refute render(view) =~ ~s|href="/m/#{scope.entity.slug}"|
  end
end
