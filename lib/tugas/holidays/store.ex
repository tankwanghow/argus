defmodule Tugas.Holidays.Store do
  @moduledoc false

  @table :tugas_holidays

  def init, do: ensure_table!()

  def get(cache_key) do
    ensure_table!()

    case :ets.lookup(@table, cache_key) do
      [{^cache_key, holidays}] -> holidays
      [] -> :miss
    end
  end

  def put(cache_key, holidays) when is_list(holidays) do
    ensure_table!()
    :ets.insert(@table, {cache_key, holidays})
    :ok
  end

  def clear do
    if table?(), do: :ets.delete_all_objects(@table)
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
