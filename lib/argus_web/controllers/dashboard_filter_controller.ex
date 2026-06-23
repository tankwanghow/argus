defmodule ArgusWeb.DashboardFilterController do
  use ArgusWeb, :controller

  alias ArgusWeb.DashboardFilter

  def update(conn, params) do
    slug = params["entity_slug"]

    if is_binary(slug) and slug != "" do
      conn
      |> DashboardFilter.put_session(slug, params)
      |> send_resp(:no_content, "")
    else
      send_resp(conn, :unprocessable_entity, "")
    end
  end
end
