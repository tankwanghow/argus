defmodule TugasWeb.DutiesFilterTest do
  use ExUnit.Case, async: true

  alias Tugas.Accounts.User
  alias Tugas.Accounts.Scope
  alias Tugas.Entities.{Entity, Membership}
  alias TugasWeb.DutiesFilter
  alias TugasWeb.DutiesFilter.Store

  @user_id "11111111-1111-4111-8111-111111111111"

  setup do
    Store.clear(@user_id)
    :ok
  end

  defp scope(role, slug) do
    %Scope{
      user: %User{id: @user_id},
      entity: %Entity{slug: slug},
      membership: %Membership{role: role},
      role: role
    }
  end

  describe "load/2" do
    test "returns role defaults when session is empty" do
      assert %{mine?: false, lifecycle: :live, query: ""} =
               DutiesFilter.load(%{}, scope(:manager, "acme"))
    end

    test "members default to Team" do
      assert %{mine?: false, lifecycle: :live, query: ""} =
               DutiesFilter.load(%{}, scope(:member, "acme"))
    end

    test "restores saved filters for the current entity" do
      session = %{
        "duties_filters" => %{
          "acme" => %{
            "mine" => "true",
            "lifecycle" => "completed",
            "query" => "tax"
          }
        }
      }

      assert %{mine?: true, lifecycle: :completed, query: "tax"} =
               DutiesFilter.load(session, scope(:manager, "acme"))
    end

    test "prefers the in-memory store over the session snapshot" do
      Store.put(@user_id, %{
        "acme" => %{"mine" => "true", "lifecycle" => "skipped", "query" => "store"}
      })

      session = %{
        "duties_filters" => %{
          "acme" => %{"mine" => "false", "lifecycle" => "live", "query" => "session"}
        }
      }

      assert %{mine?: true, lifecycle: :skipped, query: "store"} =
               DutiesFilter.load(session, scope(:manager, "acme"))
    end

    test "restores an explicit Team choice for a member (mine=false)" do
      session = %{
        "duties_filters" => %{
          "acme" => %{"mine" => "false", "lifecycle" => "live", "query" => ""}
        }
      }

      assert %{mine?: false, lifecycle: :live, query: ""} =
               DutiesFilter.load(session, scope(:member, "acme"))
    end

    test "ignores filters saved for other entities" do
      session = %{
        "duties_filters" => %{
          "other-entity" => %{
            "mine" => "true",
            "lifecycle" => "skipped",
            "query" => "other"
          }
        }
      }

      assert %{mine?: false, lifecycle: :live, query: ""} =
               DutiesFilter.load(session, scope(:manager, "acme"))
    end

    test "falls back to defaults for invalid lifecycle values" do
      session = %{
        "duties_filters" => %{
          "acme" => %{
            "mine" => "not-a-boolean",
            "lifecycle" => "bogus",
            "query" => "find me"
          }
        }
      }

      assert %{mine?: false, lifecycle: :live, query: "find me"} =
               DutiesFilter.load(session, scope(:member, "acme"))
    end

    test "restores a saved sort and defaults to due_asc" do
      session = %{
        "duties_filters" => %{
          "acme" => %{"mine" => "false", "lifecycle" => "live", "query" => "", "sort" => "title"}
        }
      }

      assert %{sort: :title} = DutiesFilter.load(session, scope(:manager, "acme"))
      assert %{sort: :due_asc} = DutiesFilter.load(%{}, scope(:manager, "beta"))
    end

    test "rejects a bogus sort value" do
      session = %{
        "duties_filters" => %{
          "acme" => %{"mine" => "false", "lifecycle" => "live", "query" => "", "sort" => "bogus"}
        }
      }

      assert %{sort: :due_asc} = DutiesFilter.load(session, scope(:manager, "acme"))
    end

    test "restores a saved someday sort" do
      session = %{
        "duties_filters" => %{
          "acme" => %{
            "mine" => "false",
            "lifecycle" => "completed",
            "query" => "",
            "sort" => "someday"
          }
        }
      }

      assert %{sort: :someday} = DutiesFilter.load(session, scope(:manager, "acme"))
    end
  end

  describe "merge_session/3" do
    test "stores normalized filter values per entity slug" do
      assert DutiesFilter.merge_session(%{}, "acme", %{
               "mine" => true,
               "lifecycle" => "completed",
               "query" => "tax",
               "sort" => "title"
             }) == %{
               "acme" => %{
                 "mine" => "true",
                 "lifecycle" => "completed",
                 "query" => "tax",
                 "sort" => "title"
               }
             }
    end

    test "rejects invalid lifecycle values" do
      entry =
        DutiesFilter.merge_session(%{}, "acme", %{
          "mine" => "true",
          "lifecycle" => "bogus",
          "query" => "tax"
        })

      assert get_in(entry, ["acme", "lifecycle"]) == "live"
    end

    test "stores calendar month per entity slug" do
      assert DutiesFilter.merge_session(%{}, "acme", %{
               "mine" => "false",
               "lifecycle" => "live",
               "query" => "",
               "sort" => "due_asc",
               "year" => "2026",
               "month" => "5"
             }) == %{
               "acme" => %{
                 "mine" => "false",
                 "lifecycle" => "live",
                 "query" => "",
                 "sort" => "due_asc",
                 "year" => "2026",
                 "month" => "5"
               }
             }
    end

    test "merges partial updates without dropping a saved calendar month" do
      existing = %{
        "acme" => %{
          "mine" => "false",
          "lifecycle" => "live",
          "query" => "",
          "sort" => "due_asc",
          "year" => "2026",
          "month" => "5"
        }
      }

      entry =
        DutiesFilter.merge_session(existing, "acme", %{
          "mine" => "true",
          "lifecycle" => "completed",
          "query" => "tax",
          "sort" => "title"
        })

      assert get_in(entry, ["acme", "year"]) == "2026"
      assert get_in(entry, ["acme", "month"]) == "5"
      assert get_in(entry, ["acme", "mine"]) == "true"
    end
  end

  describe "persist/1" do
    defp socket(assigns) do
      base = %{__changed__: %{}, current_scope: scope(:manager, "acme")}

      %Phoenix.LiveView.Socket{
        assigns: Map.merge(base, assigns),
        private: %{live_temp: %{}}
      }
    end

    test "a list-page persist (no year/month) keeps the saved calendar month" do
      # Calendar saves a month...
      socket(%{mine?: false, lifecycle: :live, query: "", sort: :due_asc, year: 2026, month: 5})
      |> DutiesFilter.persist()

      # ...then the duty list (which has no year/month assigns) persists a filter change.
      socket(%{mine?: true, lifecycle: :completed, query: "tax", sort: :title})
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
             } = Store.get(@user_id)
    end
  end

  describe "calendar month in load/2" do
    test "restores a saved calendar month" do
      session = %{
        "duties_filters" => %{
          "acme" => %{
            "mine" => "false",
            "lifecycle" => "live",
            "query" => "",
            "sort" => "due_asc",
            "year" => "2026",
            "month" => "5"
          }
        }
      }

      assert %{year: 2026, month: 5} = DutiesFilter.load(session, scope(:manager, "acme"))
    end

    test "defaults calendar month to nil when not saved" do
      assert %{year: nil, month: nil} = DutiesFilter.load(%{}, scope(:manager, "acme"))
    end

    test "rejects invalid calendar month values" do
      session = %{
        "duties_filters" => %{
          "acme" => %{
            "mine" => "false",
            "lifecycle" => "live",
            "query" => "",
            "year" => "bogus",
            "month" => "99"
          }
        }
      }

      assert %{year: nil, month: nil} = DutiesFilter.load(session, scope(:manager, "acme"))
    end
  end
end
