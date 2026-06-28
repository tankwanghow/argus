defmodule TugasWeb.Api.PairController do
  use TugasWeb, :controller

  alias Tugas.Accounts

  def create(conn, %{"pairing_code" => code}) do
    case Accounts.exchange_pairing_code(code) do
      {:ok, {token, entity}} ->
        conn
        |> put_status(:created)
        |> json(%{
          token: token,
          entity_slug: entity.slug,
          host: TugasWeb.Endpoint.url()
        })

      :error ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid_or_expired"})
    end
  end

  def create(conn, _params) do
    conn |> put_status(:unauthorized) |> json(%{error: "invalid_or_expired"})
  end
end
