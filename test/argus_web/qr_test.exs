defmodule ArgusWeb.QRTest do
  use ExUnit.Case, async: true

  test "svg/1 returns an inline SVG string for a URL" do
    svg = ArgusWeb.QR.svg("https://example.com/invitations/abc")
    assert is_binary(svg)
    assert svg =~ "<svg"
    assert svg =~ ~s(width="240.0")
  end
end
