defmodule ArgusWeb.PageController do
  use ArgusWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
