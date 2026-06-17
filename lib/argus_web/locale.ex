defmodule ArgusWeb.Locale do
  @moduledoc """
  Sets the Gettext locale for the current request / LiveView from the
  authenticated user's `locale` field, falling back to the default.
  """

  import Plug.Conn

  @supported ~w(en ms zh)
  @default "en"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    locale = locale_for(conn.assigns[:current_scope], conn.cookies["argus_locale"])
    Gettext.put_locale(ArgusWeb.Gettext, locale)

    conn
    |> assign(:locale, locale)
    |> put_session(:locale, locale)
  end

  def on_mount(:default, _params, session, socket) do
    locale = locale_for(socket.assigns[:current_scope], session["locale"])
    Gettext.put_locale(ArgusWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  defp locale_for(%{user: %{locale: l}}, _fallback) when l in @supported, do: l
  defp locale_for(_scope, fallback) when fallback in @supported, do: fallback
  defp locale_for(_scope, _fallback), do: @default
end
