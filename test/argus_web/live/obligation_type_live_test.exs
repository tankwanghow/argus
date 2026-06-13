defmodule ArgusWeb.ObligationTypeLiveTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Argus.ObligationsFixtures

  alias Argus.Obligations.Type
  alias Argus.Repo

  setup :register_and_log_in_user

  test "manager creates a custom type via the modal", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligation-types")

    assert has_element?(view, "#new-type-btn")

    view |> element("#new-type-btn") |> render_click()
    assert has_element?(view, "#type-modal")

    view
    |> form("#type-form", %{
      "type" => %{
        "name" => "SST Return",
        "recurring_interval" => "quarterly",
        "reminder_offsets" => "30,7"
      }
    })
    |> render_submit()

    assert has_element?(view, "#custom-types", "SST Return")
  end

  test "manager can clone a system preset", %{conn: conn} do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    conn = log_in_user(conn, manager.user)

    preset =
      %Type{entity_id: nil}
      |> Type.changeset(%{name: "EPF Monthly", recurring_interval: "monthly"})
      |> Repo.insert!()

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{manager.entity.slug}/obligation-types")

    view |> element("#type-#{preset.id} button", "Clone") |> render_click()
    assert has_element?(view, "#type-form")

    view |> form("#type-form", %{"type" => %{}}) |> render_submit()
    assert has_element?(view, "#custom-types", "EPF Monthly (copy)")
  end

  test "member cannot see management actions", %{conn: conn} do
    member = member_scope_on_entity(Argus.EntitiesFixtures.manager_scope_fixture().entity)
    conn = log_in_user(conn, member.user)

    {:ok, view, _html} =
      live(conn, ~p"/entities/#{member.entity.slug}/obligation-types")

    refute has_element?(view, "#new-type-btn")
  end
end
