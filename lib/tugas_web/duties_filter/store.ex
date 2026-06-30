defmodule TugasWeb.DutiesFilter.Store do
  @moduledoc """
  In-memory, server-side store for dashboard/duties list filters, keyed by a
  per-browser `filter_sid` (see `TugasWeb.DutiesFilter` and
  `TugasWeb.Plugs.FilterSession`).

  Keying by the browser session id — not the user id — keeps filters **per
  device**: two browsers (even the same user, even a shared login) never share
  filter state. The table is process-global and read on every LiveView mount, so
  filters survive live navigation between pages; it is in-memory only, so they
  reset on server restart.
  """

  @table :tugas_duties_filters

  def init, do: ensure_table!()

  def get(nil), do: %{}

  def get(sid) do
    ensure_table!()

    case :ets.lookup(@table, sid) do
      [{^sid, filters}] -> filters
      [] -> %{}
    end
  end

  def put(nil, _filters), do: :ok

  def put(sid, filters) when is_map(filters) do
    ensure_table!()
    :ets.insert(@table, {sid, filters})
    :ok
  end

  def clear(nil), do: :ok

  def clear(sid) do
    if table?(), do: :ets.delete(@table, sid)
    :ok
  end

  defp ensure_table! do
    if table?() do
      :ok
    else
      try do
        :ets.new(@table, [
          :named_table,
          :set,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])
      rescue
        ArgumentError -> :ok
      end
    end
  end

  defp table?, do: :ets.whereis(@table) != :undefined
end
