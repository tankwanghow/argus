defmodule Tugas.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    TugasWeb.DutiesFilter.Store.init()
    Tugas.Holidays.Store.init()
    Tugas.Holidays.Countries.init()

    children =
      [
        TugasWeb.Telemetry,
        Tugas.Repo,
        {DNSCluster, query: Application.get_env(:tugas, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Tugas.PubSub},
        # Start to serve requests, typically the last entry
        TugasWeb.Endpoint
      ]
      |> maybe_warm_holiday_cache_child()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tugas.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TugasWeb.DutiesFilter.Store.init()
    Tugas.Holidays.Store.init()
    Tugas.Holidays.Countries.init()
    TugasWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_warm_holiday_cache_child(children) do
    if Application.get_env(:tugas, :warm_holiday_cache, false) do
      Logger.info("[tugas] Public holiday cache warm scheduled on boot")
      [{Tugas.Holidays.WarmCache, []} | children]
    else
      children
    end
  end
end
