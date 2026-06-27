defmodule TugasWeb.DutiesFilter.Store do
  @moduledoc false

  @table :tugas_duties_filters

  def init, do: ensure_table!()

  def get(user_id) do
    ensure_table!()

    case :ets.lookup(@table, user_id) do
      [{^user_id, filters}] -> filters
      [] -> %{}
    end
  end

  def put(user_id, filters) when is_map(filters) do
    ensure_table!()
    :ets.insert(@table, {user_id, filters})
    :ok
  end

  def clear(user_id) do
    if table?(), do: :ets.delete(@table, user_id)
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
