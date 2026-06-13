defmodule ArgusWeb.ViewController do
  @moduledoc """
  Sets the `argus_view` cookie that overrides device detection, then redirects
  back to the requested path. Used by the Desktop/Mobile toggle links — these
  must be full-page navigations (not LiveView `navigate`) so the cookie is set
  and `AutoRouteByDevice` sees it on the next request.
  """
  use ArgusWeb, :controller

  @one_year 60 * 60 * 24 * 365

  def set(conn, %{"view" => view, "to" => to}) when view in ["mobile", "desktop"] do
    conn
    |> put_resp_cookie("argus_view", view, max_age: @one_year, same_site: "Lax")
    |> redirect(to: safe_local_path(to))
    |> halt()
  end

  # Only allow same-origin absolute paths — never an external URL (open redirect).
  defp safe_local_path("/" <> rest), do: "/" <> rest
  defp safe_local_path(_), do: "/entities"
end
