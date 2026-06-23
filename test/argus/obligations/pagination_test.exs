defmodule Argus.Obligations.PaginationTest do
  use ExUnit.Case, async: true

  alias Argus.Obligations.Pagination

  test "round-trips a key/id cursor" do
    cursor = %{key: "2026-06-15", id: "abc-123"}
    assert cursor |> Pagination.encode() |> Pagination.decode() == cursor
  end

  test "encode(nil) and decode(nil) are nil" do
    assert Pagination.encode(nil) == nil
    assert Pagination.decode(nil) == nil
  end

  test "decode is idempotent on an already-decoded map" do
    cursor = %{key: "x", id: "y"}
    assert Pagination.decode(cursor) == cursor
  end

  test "decode returns nil for garbage" do
    assert Pagination.decode("") == nil
    assert Pagination.decode("not-base64-$$$") == nil
    assert Pagination.decode(Base.url_encode64("not json", padding: false)) == nil
  end
end
