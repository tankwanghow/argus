defmodule TugasWeb.ObligationTypeLiveTest do
  use TugasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tugas.ObligationsFixtures

  setup :register_and_log_in_user

  test "escape closes the type editor modal", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligation-types")

    view |> element("#new-type-btn") |> render_click()
    assert has_element?(view, "#type-modal")

    view |> element("#tugas-shell") |> render_keydown()
    refute has_element?(view, "#type-modal")
  end

  test "manager creates a custom type via the modal", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligation-types")

    assert has_element?(view, "#new-type-btn")

    view |> element("#new-type-btn") |> render_click()
    assert has_element?(view, "#type-modal")

    view
    |> form("#type-form", %{
      "type" => %{
        "name" => "GST Return",
        "recurring_interval" => "quarterly",
        "reminder_offsets" => "30,7"
      }
    })
    |> render_submit()

    assert has_element?(view, "#types", "GST Return")
  end

  test "manager can clone a type", %{conn: conn} do
    manager = Tugas.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    [epf | _] =
      Tugas.Obligations.list_types(manager)
      |> Enum.filter(&(&1.name == "EPF Monthly"))

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligation-types")

    view |> element("#type-#{epf.id} button", "Clone") |> render_click()
    assert has_element?(view, "#type-form")

    view |> form("#type-form", %{"type" => %{}}) |> render_submit()
    assert has_element?(view, "#types", "EPF Monthly (copy)")
  end

  test "member cannot see management actions", %{conn: conn} do
    member = member_scope_on_entity(Tugas.EntitiesFixtures.manager_scope_fixture().entity)
    conn = log_in_user(conn, member.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{member.entity.slug}/obligation-types")

    refute has_element?(view, "#new-type-btn")
  end
end
