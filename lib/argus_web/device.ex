defmodule ArgusWeb.Device do
  @moduledoc """
  Device detection (mobile vs desktop) for routing and template choice.
  The explicit `argus_view` cookie wins; otherwise we sniff the user-agent.
  """
  import Plug.Conn

  @mobile_ua ~r/Mobile|Android|iPhone|iPod|Opera Mini|IEMobile/i

  @doc "True when the request should render the mobile UI."
  def mobile?(conn) do
    conn = fetch_cookies(conn)

    case conn.cookies["argus_view"] do
      "mobile" -> true
      "desktop" -> false
      _ -> mobile_ua?(conn)
    end
  end

  @doc "True when the user-agent header looks like a mobile device."
  def mobile_ua?(conn) do
    ua = conn |> get_req_header("user-agent") |> List.first() |> Kernel.||("")
    mobile_user_agent?(ua)
  end

  @doc "True when a raw user-agent string looks like a mobile device."
  def mobile_user_agent?(ua) when is_binary(ua), do: String.match?(ua, @mobile_ua)
  def mobile_user_agent?(_), do: false

  @doc "True when a LiveView socket should render the mobile UI."
  def mobile_from_socket?(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :user_agent) do
      ua when is_binary(ua) -> mobile_user_agent?(ua)
      _ -> false
    end
  end
end
