defmodule TugasWeb.Plugs.FilterSession do
  @moduledoc """
  Ensures a per-browser `:filter_sid` exists in the session.

  The id is opaque — it only identifies the browser session so the dashboard /
  duties list filters can be persisted server-side per device (see
  `TugasWeb.DutiesFilter` and `TugasWeb.DutiesFilter.Store`). The filter values
  themselves never touch the cookie; only this id does.
  """

  import Plug.Conn

  alias TugasWeb.DutiesFilter

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :filter_sid) do
      conn
    else
      put_session(conn, :filter_sid, DutiesFilter.new_sid())
    end
  end
end
