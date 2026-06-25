defmodule ArgusWeb.TodoLiveTest do
  use ArgusWeb.ConnCase, async: true

  @moduletag :todos

  import Phoenix.LiveViewTest
  import Argus.EntitiesFixtures, only: [entity_scope_fixture: 0]
  import Argus.ObligationsFixtures, only: [member_scope_on_entity: 1]

  @mobile_ua "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"

  defp mobile_conn(conn, user) do
    conn |> log_in_user(user) |> put_req_header("user-agent", @mobile_ua)
  end

  test "desktop todos page loads with create controls", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, html} = live(conn, ~p"/entities/#{scope.entity.slug}/todos")

    assert html =~ "Todos"
    assert has_element?(view, "#new-todo-btn")
    assert has_element?(view, "#todos-empty")
  end

  test "member creates, completes, and deletes a todo on desktop", %{conn: conn} do
    admin = entity_scope_fixture()
    scope = member_scope_on_entity(admin.entity)
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/todos")

    view |> element("#new-todo-btn") |> render_click()
    assert has_element?(view, "#todo-modal")

    view
    |> form("#todo-form", %{"todo" => %{"title" => "Restock pantry"}})
    |> render_submit()

    assert has_element?(view, "#todos-list", "Restock pantry")

    todo = hd(Argus.Todos.list_todos(scope))

    view |> element("#todo-complete-#{todo.id}") |> render_click()
    assert has_element?(view, "#todo-#{todo.id}.opacity-60")

    view |> element("#todo-#{todo.id} button", "Delete") |> render_click()
    assert has_element?(view, "#todos-empty")
  end

  test "escape closes the todo editor modal", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/entities/#{scope.entity.slug}/todos")

    view |> element("#new-todo-btn") |> render_click()
    assert has_element?(view, "#todo-modal")

    view |> element("#argus-shell") |> render_keydown()
    refute has_element?(view, "#todo-modal")
  end

  test "todo created by one user appears for another team member", %{conn: conn} do
    creator = entity_scope_fixture()
    teammate = member_scope_on_entity(creator.entity)

    {:ok, _} = Argus.Todos.create_todo(creator, %{title: "Shared task"})

    conn = log_in_user(conn, teammate.user)
    {:ok, view, _html} = live(conn, ~p"/entities/#{teammate.entity.slug}/todos")

    assert has_element?(view, "#todos-list", "Shared task")
  end

  test "mobile todos page loads with create controls", %{conn: conn} do
    scope = entity_scope_fixture()
    conn = mobile_conn(conn, scope.user)

    {:ok, view, html} = live(conn, ~p"/m/#{scope.entity.slug}/todos")

    assert html =~ "Todos"
    assert has_element?(view, "#m-new-todo-btn")
    assert has_element?(view, "#m-todos-empty")
  end

  test "mobile member creates a todo", %{conn: conn} do
    admin = entity_scope_fixture()
    scope = member_scope_on_entity(admin.entity)
    conn = mobile_conn(conn, scope.user)

    {:ok, view, _html} = live(conn, ~p"/m/#{scope.entity.slug}/todos")

    view |> element("#m-new-todo-btn") |> render_click()

    view
    |> form("#m-todo-form", %{"todo" => %{"title" => "Mobile quick task"}})
    |> render_submit()

    assert has_element?(view, "#m-todos-list", "Mobile quick task")
  end
end
