defmodule ArgusWeb.DashboardLive.Index do
  use ArgusWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="dashboard-stub">
        <.header>
          Dashboard
          <:subtitle>{@current_scope.entity.name}</:subtitle>
        </.header>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
