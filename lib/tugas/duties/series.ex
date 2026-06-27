defmodule Tugas.Duties.Series do
  @moduledoc """
  Recurrence series helpers.
  """

  import Ecto.Query, warn: false

  alias Tugas.Duties.Duty
  alias Tugas.Repo

  def ended?(series_id) do
    Duty
    |> where([o], o.series_id == ^series_id and not is_nil(o.series_ended_at))
    |> Repo.exists?()
  end
end
