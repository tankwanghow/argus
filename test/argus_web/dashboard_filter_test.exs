defmodule ArgusWeb.DashboardFilterTest do
  use ExUnit.Case, async: true

  alias Argus.Accounts.User
  alias Argus.Accounts.Scope
  alias Argus.Entities.{Entity, Membership}
  alias ArgusWeb.DashboardFilter
  alias ArgusWeb.DashboardFilter.Store

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
               DashboardFilter.load(%{}, scope(:manager, "acme"))
    end

    test "members default to Mine" do
      assert %{mine?: true, lifecycle: :live, query: ""} =
               DashboardFilter.load(%{}, scope(:member, "acme"))
    end

    test "restores saved filters for the current entity" do
      session = %{
        "dashboard_filters" => %{
          "acme" => %{
            "mine" => "true",
            "lifecycle" => "completed",
            "query" => "tax"
          }
        }
      }

      assert %{mine?: true, lifecycle: :completed, query: "tax"} =
               DashboardFilter.load(session, scope(:manager, "acme"))
    end

    test "prefers the in-memory store over the session snapshot" do
      Store.put(@user_id, %{
        "acme" => %{"mine" => "true", "lifecycle" => "skipped", "query" => "store"}
      })

      session = %{
        "dashboard_filters" => %{
          "acme" => %{"mine" => "false", "lifecycle" => "live", "query" => "session"}
        }
      }

      assert %{mine?: true, lifecycle: :skipped, query: "store"} =
               DashboardFilter.load(session, scope(:manager, "acme"))
    end

    test "restores an explicit Team choice for a member (mine=false)" do
      session = %{
        "dashboard_filters" => %{
          "acme" => %{"mine" => "false", "lifecycle" => "live", "query" => ""}
        }
      }

      assert %{mine?: false, lifecycle: :live, query: ""} =
               DashboardFilter.load(session, scope(:member, "acme"))
    end

    test "ignores filters saved for other entities" do
      session = %{
        "dashboard_filters" => %{
          "other-entity" => %{
            "mine" => "true",
            "lifecycle" => "skipped",
            "query" => "other"
          }
        }
      }

      assert %{mine?: false, lifecycle: :live, query: ""} =
               DashboardFilter.load(session, scope(:manager, "acme"))
    end

    test "falls back to defaults for invalid lifecycle values" do
      session = %{
        "dashboard_filters" => %{
          "acme" => %{
            "mine" => "not-a-boolean",
            "lifecycle" => "bogus",
            "query" => "find me"
          }
        }
      }

      assert %{mine?: true, lifecycle: :live, query: "find me"} =
               DashboardFilter.load(session, scope(:member, "acme"))
    end

    test "restores a saved sort and defaults to due_asc" do
      session = %{
        "dashboard_filters" => %{
          "acme" => %{"mine" => "false", "lifecycle" => "live", "query" => "", "sort" => "title"}
        }
      }

      assert %{sort: :title} = DashboardFilter.load(session, scope(:manager, "acme"))
      assert %{sort: :due_asc} = DashboardFilter.load(%{}, scope(:manager, "beta"))
    end

    test "rejects a bogus sort value" do
      session = %{
        "dashboard_filters" => %{
          "acme" => %{"mine" => "false", "lifecycle" => "live", "query" => "", "sort" => "bogus"}
        }
      }

      assert %{sort: :due_asc} = DashboardFilter.load(session, scope(:manager, "acme"))
    end

    test "restores a saved date_filter and defaults to dated" do
      session = %{
        "dashboard_filters" => %{
          "acme" => %{
            "mine" => "false",
            "lifecycle" => "completed",
            "query" => "",
            "sort" => "recent",
            "date_filter" => "someday"
          }
        }
      }

      assert %{date_filter: :someday} = DashboardFilter.load(session, scope(:manager, "acme"))
      assert %{date_filter: :dated} = DashboardFilter.load(%{}, scope(:manager, "beta"))
    end

    test "rejects a bogus date_filter" do
      session = %{
        "dashboard_filters" => %{
          "acme" => %{
            "mine" => "false",
            "lifecycle" => "live",
            "query" => "",
            "sort" => "due_asc",
            "date_filter" => "nope"
          }
        }
      }

      assert %{date_filter: :dated} = DashboardFilter.load(session, scope(:manager, "acme"))
    end
  end

  describe "merge_session/3" do
    test "stores normalized filter values per entity slug" do
      assert DashboardFilter.merge_session(%{}, "acme", %{
               "mine" => true,
               "lifecycle" => "completed",
               "query" => "tax",
               "sort" => "title",
               "date_filter" => "dated"
             }) == %{
               "acme" => %{
                 "mine" => "true",
                 "lifecycle" => "completed",
                 "query" => "tax",
                 "sort" => "title",
                 "date_filter" => "dated"
               }
             }
    end

    test "rejects invalid lifecycle values" do
      entry =
        DashboardFilter.merge_session(%{}, "acme", %{
          "mine" => "true",
          "lifecycle" => "bogus",
          "query" => "tax"
        })

      assert get_in(entry, ["acme", "lifecycle"]) == "live"
    end
  end
end
