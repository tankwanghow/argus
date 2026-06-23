defmodule ArgusWeb.ObligationLive.IndexHelpersTest do
  use Argus.DataCase, async: true

  import Argus.ObligationsFixtures

  alias ArgusWeb.ObligationLive.IndexHelpers, as: Index
  alias Argus.Obligations.Urgency

  test "sorts/1 includes urgency only for live" do
    assert {"urgency", _} = List.keyfind(Index.sorts(:live), "urgency", 0)
    refute List.keyfind(Index.sorts(:completed), "urgency", 0)
  end

  test "effective_sort keeps urgency on live, downgrades elsewhere" do
    assert Index.effective_sort(:urgency, :live) == :urgency
    assert Index.effective_sort(:urgency, :completed) == :due_asc
    assert Index.effective_sort(:title, :completed) == :title
  end

  test "parse_sort whitelists with due_asc default" do
    assert Index.parse_sort("title") == :title
    assert Index.parse_sort("bogus") == :due_asc
  end

  test "load_page returns paged rows for a non-urgency sort" do
    manager = Argus.EntitiesFixtures.manager_scope_fixture()
    type = type_fixture(manager.entity)

    for {title, due} <- [{"a", ~D[2026-01-01]}, {"b", ~D[2026-02-01]}, {"c", ~D[2026-03-01]}] do
      {:ok, _} =
        Argus.Obligations.create_obligation(manager, %{
          title: title,
          obligation_type_id: type.id,
          due_by: due,
          open_note: "n"
        })
    end

    today = Urgency.today_for(manager.entity.timezone)
    page = Index.load_page(manager, today, false, :live, "", :due_asc, nil)

    assert Enum.map(page.rows, & &1.obligation.title) == ["a", "b", "c"]
    assert page.end?
    assert Enum.all?(page.rows, &Map.has_key?(&1, :tier))
  end
end
