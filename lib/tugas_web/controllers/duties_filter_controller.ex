defmodule TugasWeb.DutiesFilterController do
  use TugasWeb, :controller

  alias TugasWeb.DutiesFilter

  def update(conn, params) do
    slug = params["entity_slug"]

    if is_binary(slug) and slug != "" do
      conn
      |> DutiesFilter.put_session(slug, params)
      |> send_resp(:no_content, "")
    else
      send_resp(conn, :unprocessable_entity, "")
    end
  end
end
