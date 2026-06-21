defmodule ArgusWeb.Paths do
  @moduledoc """
  Device-aware path helpers.

  Entity work always lives at `/entities/:slug/...` (desktop) or `/m/:slug/...`
  (mobile). Use `view_mode/2` for explicit UI toggles — always via `href`, never
  LiveView `navigate`, so the cookie is set and `AutoRouteByDevice` runs.
  """
  use ArgusWeb, :verified_routes

  @doc "Full-page URL that sets the `argus_view` cookie then redirects to `to`."
  def view_mode(mode, to) when mode in ["mobile", "desktop"] and is_binary(to) do
    ~p"/view-mode?#{[mode: mode, to: to]}"
  end

  def desktop_entity(slug), do: ~p"/entities/#{slug}"
  def mobile_entity(slug), do: ~p"/m/#{slug}"
end
