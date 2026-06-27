defmodule TugasWeb.LocaleController do
  @moduledoc """
  Persists the logged-in user's UI locale and redirects back to the
  referring page, so `TugasWeb.Locale` re-applies it on the next request.
  """
  use TugasWeb, :controller

  alias Tugas.Accounts
  alias Tugas.Accounts.User

  @locales ~w(en ms zh)

  def update(conn, %{"locale" => locale}) when locale in @locales do
    case conn.assigns[:current_scope] do
      %{user: %User{} = user} -> Accounts.update_user_locale(user, locale)
      _ -> :noop
    end

    conn
    |> put_resp_cookie("tugas_locale", locale, max_age: 60 * 60 * 24 * 365, same_site: "Lax")
    |> redirect(to: return_path(conn))
  end

  def update(conn, _params), do: redirect(conn, to: return_path(conn))

  defp return_path(conn) do
    conn |> get_req_header("referer") |> List.first() |> safe_path()
  end

  defp safe_path(referer) when is_binary(referer) do
    uri = URI.parse(referer)
    path = uri.path || "/"
    app_host = TugasWeb.Endpoint.config(:url)[:host] || "localhost"
    host_ok = is_nil(uri.host) or uri.host == app_host

    if host_ok and String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
      path <> if(uri.query, do: "?" <> uri.query, else: "")
    else
      ~p"/"
    end
  end

  defp safe_path(_), do: ~p"/"
end
