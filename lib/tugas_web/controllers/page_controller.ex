defmodule TugasWeb.PageController do
  use TugasWeb, :controller

  def home(conn, _params) do
    # Logged-in users land on their workspace (/entities auto-forwards to the
    # single entity's dashboard, or shows the picker); anonymous users see the
    # marketing page.
    case conn.assigns.current_scope do
      %{user: user} -> redirect(conn, to: TugasWeb.UserAuth.default_entity_path(user))
      _ -> render(conn, :home)
    end
  end
end
