defmodule TugasWeb.DashboardLive.Index do
  use TugasWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="dashboard" class="tugas-page">
        <.header>Dashboard</.header>
        <div class="tugas-page-body py-12 text-center text-base-content/70">
          <p class="text-lg">Dashboard coming soon.</p>
          <p class="mt-2 text-sm">
            Temporary placeholder for {@current_scope.entity.name}.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("close_modal_on_escape", _params, socket), do: {:noreply, socket}
end
