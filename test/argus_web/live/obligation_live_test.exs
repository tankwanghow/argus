defmodule ArgusWeb.ObligationLiveTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.ObligationsFixtures

  setup :register_and_log_in_user

  test "manager creates obligation via form", %{conn: conn} do
    {scope, _} = manager_obligation_scope_fixture()
    conn = log_in_user(conn, scope.user)
    assignee = member_fixture(scope.entity)
    type = type_fixture(scope.entity)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/new")

    view
    |> form("#obligation-create-form", %{
      "obligation" => %{
        "title" => "EPF June",
        "obligation_type_id" => type.id,
        "primary_assignee_id" => assignee.id,
        "due_by" => "2026-06-30",
        "open_note" => "Submit on time"
      }
    })
    |> render_submit()

    {path, _flash} = assert_redirect(view)
    assert path =~ "/obligations/"
  end

  test "start_progress from show page", %{conn: conn} do
    {scope, obligation} = assigned_member_scope_fixture()
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#start-progress-btn") |> render_click()
    assert render(view) =~ "in_progress"
  end

  test "done modal requires next due for recurring obligations", %{conn: conn} do
    {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#done-btn") |> render_click()
    assert has_element?(view, "#done-modal")

    view |> form("#done-form", %{"done" => %{"next_due_by" => ""}}) |> render_submit()

    assert render(view) =~ "Next due date is required"
  end

  test "complete recurring obligation with next due spawns successor", %{conn: conn} do
    {scope, obligation} = recurring_primary_scope_fixture(interval: "monthly")
    conn = log_in_user(conn, scope.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{scope.entity.slug}/obligations/#{obligation.id}")

    view |> element("#done-btn") |> render_click()

    view |> form("#done-form", %{"done" => %{"next_due_by" => "2026-07-15"}}) |> render_submit()

    assert_redirect(view, ~p"/entities/#{scope.entity.slug}/obligations")
  end
end
