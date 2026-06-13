defmodule ArgusWeb.ObligationTypeLive.Index do
  use ArgusWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="obligation-types-stub">
        <.header>Obligation types</.header>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
