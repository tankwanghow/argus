defmodule ArgusWeb.ViewModeController do
  @moduledoc """
  Pins the user's UI preference (mobile vs. desktop) to a cookie so
  `ArgusWeb.Plugs.AutoRouteByDevice` respects their explicit choice
  across sessions.
  """
  use ArgusWeb, :controller

  @cookie_max_age 60 * 60 * 24 * 365

  def set(conn, %{"to" => to} = params) do
    mode = params["mode"] || params["view"]

    if mode in ["mobile", "desktop"] and is_binary(to) do
      conn
      |> put_resp_cookie("argus_view", mode, max_age: @cookie_max_age, same_site: "Lax")
      |> redirect(to: safe_redirect_path(to))
    else
      redirect(conn, to: ~p"/")
    end
  end

  def set(conn, _params), do: redirect(conn, to: ~p"/")

  defp safe_redirect_path("/" <> _ = path), do: path
  defp safe_redirect_path(_), do: ~p"/entities"
end
