defmodule ArgusWeb.ObligationLive.IndexHelpersTest do
  use Argus.DataCase, async: true

  import Argus.ObligationsFixtures

  alias ArgusWeb.ObligationLive.IndexHelpers, as: Index
  alias Argus.Obligations.Urgency

  test "parse_sort whitelists with due_asc default" do
    assert Index.parse_sort("title") == :title
    assert Index.parse_sort("bogus") == :due_asc
  end

  test "date_filter vocabulary + lifecycle-aware sorts" do
    assert {"someday", "Someday"} = List.keyfind(Index.date_filters(), "someday", 0)
    assert Index.parse_date_filter("all_dates") == :all_dates
    assert Index.parse_date_filter("bogus") == :dated

    # urgency only on live × dated; recent only on someday; due on dated/all; title always
    assert {"urgency", _} = List.keyfind(Index.sorts(:live, :dated), "urgency", 0)
    refute List.keyfind(Index.sorts(:live, :all_dates), "urgency", 0)
    refute List.keyfind(Index.sorts(:completed, :dated), "urgency", 0)
    assert {"recent", _} = List.keyfind(Index.sorts(:completed, :someday), "recent", 0)
    refute List.keyfind(Index.sorts(:live, :dated), "recent", 0)
    assert {"due_asc", _} = List.keyfind(Index.sorts(:completed, :all_dates), "due_asc", 0)
    refute List.keyfind(Index.sorts(:live, :someday), "due_asc", 0)

    assert Index.effective_sort(:urgency, :live, :dated) == :urgency
    assert Index.effective_sort(:urgency, :live, :all_dates) == :due_asc
    assert Index.effective_sort(:due_asc, :live, :someday) == :recent
    assert Index.effective_sort(:recent, :completed, :dated) == :due_asc
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
    page = Index.load_page(manager, today, false, :live, :dated, "", :due_asc, nil)

    assert Enum.map(page.rows, & &1.obligation.title) == ["a", "b", "c"]
    assert page.end?
    assert Enum.all?(page.rows, &Map.has_key?(&1, :tier))
  end

  describe "load_page urgency on live" do
    setup do
      manager = Argus.EntitiesFixtures.manager_scope_fixture()
      # reminder offset 30 days => due within 30d is due_soon, overdue is past.
      type = type_fixture(manager.entity, reminder_offsets: "30")
      today = ~D[2026-06-01]

      mk = fn title, due ->
        {:ok, o} =
          Argus.Obligations.create_obligation(manager, %{
            title: title,
            obligation_type_id: type.id,
            due_by: due,
            open_note: "n"
          })

        o
      end

      overdue = mk.("overdue", ~D[2026-05-01])
      soon = mk.("soon", ~D[2026-06-10])
      ok = mk.("ok", ~D[2026-09-01])
      far = mk.("far", ~D[2027-12-01])
      %{manager: manager, today: today, overdue: overdue, soon: soon, ok: ok, far: far}
    end

    test "ranks overdue, then due_soon, then ok by due date; far tail loads last",
         %{manager: m, today: today, overdue: o, soon: s, ok: k, far: f} do
      p1 =
        ArgusWeb.ObligationLive.IndexHelpers.load_page(
          m,
          today,
          false,
          :live,
          :dated,
          "",
          :urgency,
          nil
        )

      assert Enum.map(p1.rows, & &1.obligation.id) == [o.id, s.id, k.id]
      refute p1.end?

      p2 =
        ArgusWeb.ObligationLive.IndexHelpers.load_page(
          m,
          today,
          false,
          :live,
          :dated,
          "",
          :urgency,
          p1.cursor
        )

      assert Enum.map(p2.rows, & &1.obligation.id) == [f.id]
      assert p2.end?
    end
  end
end
