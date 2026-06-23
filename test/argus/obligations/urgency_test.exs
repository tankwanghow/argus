defmodule Argus.Obligations.UrgencyTest do
  use ExUnit.Case, async: true

  alias Argus.Obligations.Urgency
  alias Argus.Obligations.Type

  @today ~D[2026-06-13]

  test "overdue when due_by is in the past" do
    type = %Type{reminder_offsets: "7,1"}
    assert Urgency.classify(type, ~D[2026-06-10], @today) == :overdue
  end

  test "due_soon when within reminder offset" do
    type = %Type{reminder_offsets: "7,1"}
    assert Urgency.classify(type, ~D[2026-06-18], @today) == :due_soon
  end

  test "ok when outside reminder offsets" do
    type = %Type{reminder_offsets: "7,1"}
    assert Urgency.classify(type, ~D[2026-07-01], @today) == :ok
  end

  test "due today is due_soon, not overdue" do
    type = %Type{reminder_offsets: "7,1"}
    assert Urgency.classify(type, @today, @today) == :due_soon
  end

  describe "tier/3 with multiple offsets (min=1, max=30, step≈9.67)" do
    setup do
      %{type: %Type{reminder_offsets: "30,7,1"}}
    end

    test "overdue when due_by is in the past", %{type: type} do
      assert Urgency.tier(type, ~D[2026-06-11], @today) == :overdue
    end

    test "ok when beyond the largest offset", %{type: type} do
      assert Urgency.tier(type, ~D[2026-07-18], @today) == :ok
    end

    test "approaching at the max boundary", %{type: type} do
      assert Urgency.tier(type, ~D[2026-07-13], @today) == :approaching
    end

    test "approaching in the loosest third", %{type: type} do
      assert Urgency.tier(type, ~D[2026-07-08], @today) == :approaching
    end

    test "due_soon in the middle third", %{type: type} do
      assert Urgency.tier(type, ~D[2026-06-28], @today) == :due_soon
    end

    test "critical in the tightest third", %{type: type} do
      assert Urgency.tier(type, ~D[2026-06-18], @today) == :critical
    end

    test "critical when due today", %{type: type} do
      assert Urgency.tier(type, @today, @today) == :critical
    end
  end

  describe "tier/3 with a single offset (min=7, max=14, step≈2.33)" do
    setup do
      %{type: %Type{reminder_offsets: "7"}}
    end

    test "ok beyond offset + 7", %{type: type} do
      assert Urgency.tier(type, ~D[2026-06-28], @today) == :ok
    end

    test "approaching just inside offset + 7", %{type: type} do
      assert Urgency.tier(type, ~D[2026-06-26], @today) == :approaching
    end

    test "due_soon in the middle third", %{type: type} do
      assert Urgency.tier(type, ~D[2026-06-23], @today) == :due_soon
    end

    test "critical in the tightest third", %{type: type} do
      assert Urgency.tier(type, ~D[2026-06-21], @today) == :critical
    end

    test "overdue in the past", %{type: type} do
      assert Urgency.tier(type, ~D[2026-06-12], @today) == :overdue
    end
  end

  test "classify and tier return :none when due_by is nil" do
    type = %Type{reminder_offsets: "30,7,1"}
    assert Urgency.classify(type, nil, ~D[2026-06-23]) == :none
    assert Urgency.tier(type, nil, ~D[2026-06-23]) == :none
  end
end
