defmodule ArgusWeb.FormatDatetimeTest do
  use ExUnit.Case, async: true

  alias ArgusWeb.CoreComponents

  # 2026-01-15 23:30 UTC is already 2026-01-16 07:30 in Kuala Lumpur (UTC+8).
  @utc ~U[2026-01-15 23:30:00Z]
  @tz "Asia/Kuala_Lumpur"

  describe "format_datetime/3" do
    test "renders in the entity timezone" do
      assert CoreComponents.format_datetime(@utc, @tz) == "16 Jan 2026, 07:30"
      assert CoreComponents.format_datetime(@utc, @tz, :short) == "2026-01-16 07:30"
    end

    test "falls back to the instant for an invalid/blank zone" do
      assert CoreComponents.format_datetime(@utc, "") == "15 Jan 2026, 23:30"
      assert CoreComponents.format_datetime(@utc, "Not/AZone") == "15 Jan 2026, 23:30"
    end

    test "blank for nil" do
      assert CoreComponents.format_datetime(nil, @tz) == ""
    end
  end

  describe "format_zoned_date/3" do
    test "takes the date after shifting (lands on the local day)" do
      assert CoreComponents.format_zoned_date(@utc, @tz, :short) == "2026-01-16"
      assert CoreComponents.format_zoned_date(@utc, @tz) == "16 Jan 2026"
    end

    test "nil for nil" do
      assert CoreComponents.format_zoned_date(nil, @tz) == nil
    end
  end

  describe "format_date/2" do
    test "plain calendar date is never shifted" do
      assert CoreComponents.format_date(~D[2026-01-15]) == "15 Jan 2026"
      assert CoreComponents.format_date(~D[2026-01-15], :short) == "2026-01-15"
      assert CoreComponents.format_date(nil) == "—"
    end
  end
end
