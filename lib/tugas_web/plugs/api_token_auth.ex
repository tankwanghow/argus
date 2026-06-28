defmodule TugasWeb.Plugs.ApiTokenAuth do
  @moduledoc """
  Authenticates an API request via `Authorization: Bearer <token>`.

  On success assigns `:current_scope` (a user-only `%Scope{}`) and
  `:api_token_entity_id`. On any failure sends 401 JSON and halts.
  """
  import Plug.Conn

  alias Tugas.Accounts
  alias Tugas.Accounts.Scope

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {user, entity_id} when is_binary(entity_id) <- Accounts.fetch_api_token_user(token) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> assign(:api_token_entity_id, entity_id)
    else
      _ -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
    |> halt()
  end
end
