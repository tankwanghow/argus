defmodule TugasWeb.DutiesFilterTest do
  use ExUnit.Case, async: true

  alias Tugas.Accounts.User
  alias Tugas.Accounts.Scope
  alias Tugas.Entities.{Entity, Membership}
  alias TugasWeb.DutiesFilter
  alias TugasWeb.DutiesFilter.Store

  setup do
    sid = DutiesFilter.new_sid()
    on_exit(fn -> Store.clear(sid) end)
    %{sid: sid}
  end

  defp scope(role, slug) do
    %Scope{
      user: %User{id: "11111111-1111-4111-8111-111111111111"},
      entity: %Entity{slug: slug},
      membership: %Membership{role: role},
      role: role
    }
  end

  defp session(sid), do: %{"filter_sid" => sid}

  describe "load/2" do
    test "returns role defaults when nothing is stored", %{sid: sid} do
      assert %{mine?: false, lifecycle: :live, query: ""} =
               DutiesFilter.load(session(sid), scope(:manager, "acme"))
    end

    test "members default to Team", %{sid: sid} do
      assert %{mine?: false, lifecycle: :live, query: ""} =
               DutiesFilter.load(session(sid), scope(:member, "acme"))
    end

    test "restores stored filters for the current entity", %{sid: sid} do
      Store.put(sid, %{
        "acme" => %{"mine" => "true", "lifecycle" => "completed", "query" => "tax"}
      })

      assert %{mine?: true, lifecycle: :completed, query: "tax"} =
               DutiesFilter.load(session(sid), scope(:manager, "acme"))
    end

    test "restores an explicit Team choice for a member (mine=false)", %{sid: sid} do
      Store.put(sid, %{"acme" => %{"mine" => "false", "lifecycle" => "live", "query" => ""}})

      assert %{mine?: false, lifecycle: :live, query: ""} =
               DutiesFilter.load(session(sid), scope(:member, "acme"))
    end

    test "ignores filters stored for other entities", %{sid: sid} do
      Store.put(sid, %{
        "other-entity" => %{"mine" => "true", "lifecycle" => "skipped", "query" => "other"}
      })

      assert %{mine?: false, lifecycle: :live, query: ""} =
               DutiesFilter.load(session(sid), scope(:manager, "acme"))
    end

    test "is per-browser: another sid's filters are not visible", %{sid: sid} do
      other = DutiesFilter.new_sid()
      on_exit(fn -> Store.clear(other) end)

      Store.put(other, %{"acme" => %{"mine" => "true", "lifecycle" => "skipped", "query" => "x"}})

      assert %{mine?: false, lifecycle: :live, query: ""} =
               DutiesFilter.load(session(sid), scope(:manager, "acme"))
    end

    test "falls back to defaults for invalid values", %{sid: sid} do
      Store.put(sid, %{
        "acme" => %{"mine" => "not-a-boolean", "lifecycle" => "bogus", "query" => "find me"}
      })

      assert %{mine?: false, lifecycle: :live, query: "find me"} =
               DutiesFilter.load(session(sid), scope(:member, "acme"))
    end

    test "restores a stored sort and defaults to due_asc", %{sid: sid} do
      Store.put(sid, %{
        "acme" => %{"mine" => "false", "lifecycle" => "live", "query" => "", "sort" => "title"}
      })

      assert %{sort: :title} = DutiesFilter.load(session(sid), scope(:manager, "acme"))
      assert %{sort: :due_asc} = DutiesFilter.load(session(sid), scope(:manager, "beta"))
    end

    test "rejects a bogus sort value", %{sid: sid} do
      Store.put(sid, %{
        "acme" => %{"mine" => "false", "lifecycle" => "live", "query" => "", "sort" => "bogus"}
      })

      assert %{sort: :due_asc} = DutiesFilter.load(session(sid), scope(:manager, "acme"))
    end

    test "restores a stored calendar month", %{sid: sid} do
      Store.put(sid, %{
        "acme" => %{
          "mine" => "false",
          "lifecycle" => "live",
          "query" => "",
          "year" => "2026",
          "month" => "5"
        }
      })

      assert %{year: 2026, month: 5} = DutiesFilter.load(session(sid), scope(:manager, "acme"))
    end

    test "defaults calendar month to nil when not stored", %{sid: sid} do
      assert %{year: nil, month: nil} = DutiesFilter.load(session(sid), scope(:manager, "acme"))
    end

    test "rejects invalid calendar month values", %{sid: sid} do
      Store.put(sid, %{
        "acme" => %{
          "mine" => "false",
          "lifecycle" => "live",
          "query" => "",
          "year" => "bogus",
          "month" => "99"
        }
      })

      assert %{year: nil, month: nil} = DutiesFilter.load(session(sid), scope(:manager, "acme"))
    end
  end

  describe "persist/1" do
    defp socket(sid, assigns) do
      base = %{__changed__: %{}, current_scope: scope(:manager, "acme"), filter_sid: sid}
      %Phoenix.LiveView.Socket{assigns: Map.merge(base, assigns)}
    end

    test "writes the current filter values to the store", %{sid: sid} do
      socket(sid, %{
        mine?: true,
        lifecycle: :completed,
        query: "tax",
        sort: :title,
        year: 2026,
        month: 5
      })
      |> DutiesFilter.persist()

      assert %{
               "acme" => %{
                 "mine" => "true",
                 "lifecycle" => "completed",
                 "query" => "tax",
                 "sort" => "title",
                 "year" => "2026",
                 "month" => "5"
               }
             } = Store.get(sid)
    end

    test "a list-page persist (no year/month) keeps the stored calendar month", %{sid: sid} do
      # Calendar saves a month...
      socket(sid, %{
        mine?: false,
        lifecycle: :live,
        query: "",
        sort: :due_asc,
        year: 2026,
        month: 5
      })
      |> DutiesFilter.persist()

      # ...then the duty list (which has no year/month assigns) persists a filter change.
      socket(sid, %{mine?: true, lifecycle: :completed, query: "tax", sort: :title})
      |> DutiesFilter.persist()

      assert %{
               "acme" => %{
                 "mine" => "true",
                 "lifecycle" => "completed",
                 "query" => "tax",
                 "sort" => "title",
                 "year" => "2026",
                 "month" => "5"
               }
             } = Store.get(sid)
    end
  end
end
