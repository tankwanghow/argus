defmodule ArgusWeb.UrgencyBadgeTest do
  use ExUnit.Case, async: true

  alias ArgusWeb.UrgencyBadge

  @today ~D[2026-06-13]

  describe "tier_border/1" do
    test "maps each graded tier to a border class" do
      assert UrgencyBadge.tier_border(:overdue) == "border-error"
      assert UrgencyBadge.tier_border(:critical) == "border-error/60"
      assert UrgencyBadge.tier_border(:due_soon) == "border-warning"
      assert UrgencyBadge.tier_border(:approaching) == "border-warning/40"
      assert UrgencyBadge.tier_border(:ok) == "border-transparent"
    end
  end

  describe "badge_text/3" do
    test "no badge when on track" do
      assert UrgencyBadge.badge_text(:ok, ~D[2026-07-30], @today) == nil
    end

    test "overdue counts days past due" do
      assert UrgencyBadge.badge_text(:overdue, ~D[2026-06-11], @today) == "2d overdue"
    end

    test "due today reads as a phrase, not 0d" do
      assert UrgencyBadge.badge_text(:critical, @today, @today) == "Due today"
    end

    test "future cycles count days left regardless of tier" do
      assert UrgencyBadge.badge_text(:critical, ~D[2026-06-16], @today) == "3d left"
      assert UrgencyBadge.badge_text(:due_soon, ~D[2026-06-25], @today) == "12d left"
      assert UrgencyBadge.badge_text(:approaching, ~D[2026-07-08], @today) == "25d left"
    end
  end

  describe "badge_class/1" do
    test "maps each tier to a daisyUI badge class" do
      assert UrgencyBadge.badge_class(:overdue) == "badge-error"
      assert UrgencyBadge.badge_class(:critical) == "badge-error badge-soft"
      assert UrgencyBadge.badge_class(:due_soon) == "badge-warning"
      assert UrgencyBadge.badge_class(:approaching) == "badge-warning badge-soft"
    end
  end
end
