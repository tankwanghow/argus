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
end