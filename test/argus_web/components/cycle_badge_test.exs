defmodule ArgusWeb.CycleBadgeTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import ArgusWeb.CycleBadge

  alias Argus.Obligations.Obligation

  @today ~D[2026-06-23]
  @at ~U[2026-03-22 04:30:00Z]

  defp badge_html(assigns) do
    render_component(&cycle_badge/1, Map.merge(%{today: @today, in_error: false}, assigns))
  end

  test "live overdue cycle shows the countdown and a data-urgency hook" do
    html =
      badge_html(%{
        cycle_status: :live,
        tier: :overdue,
        obligation: %Obligation{due_by: ~D[2026-06-20]}
      })

    assert html =~ "3d overdue"
    assert html =~ ~s(data-urgency="overdue")
    assert html =~ "text-error"
  end

  test "live on-track dated cycle renders nothing" do
    assert badge_html(%{
             cycle_status: :live,
             tier: :ok,
             obligation: %Obligation{due_by: ~D[2027-01-01]}
           }) ==
             ""
  end

  test "live undated (Someday) cycle shows a green Anytime badge" do
    html =
      badge_html(%{cycle_status: :live, tier: :none, obligation: %Obligation{due_by: nil}})

    assert html =~ "Anytime"
    assert html =~ "text-success"
  end

  test "completed cycle shows Completed + date in success colour" do
    html =
      badge_html(%{
        cycle_status: :completed,
        tier: :ok,
        obligation: %Obligation{completed_at: @at}
      })

    assert html =~ "Completed"
    assert html =~ "2026-03-22"
    assert html =~ "bg-success"
  end

  test "completed-in-error cycle uses the error colour" do
    html =
      badge_html(%{
        cycle_status: :completed,
        tier: :ok,
        in_error: true,
        obligation: %Obligation{completed_at: @at}
      })

    assert html =~ "Completed with error"
    assert html =~ "bg-error"
  end

  test "skipped cycle shows Skipped + closed date in warning colour" do
    html =
      badge_html(%{cycle_status: :skipped, tier: :ok, obligation: %Obligation{closed_at: @at}})

    assert html =~ "Skipped"
    assert html =~ "2026-03-22"
    assert html =~ "bg-warning"
  end
end
