defmodule Tugas.Obligations.Series do
  @moduledoc """
  Recurrence series helpers.
  """

  import Ecto.Query, warn: false

  alias Tugas.Obligations.Obligation
  alias Tugas.Repo

  def ended?(series_id) do
    Obligation
    |> where([o], o.series_id == ^series_id and not is_nil(o.series_ended_at))
    |> Repo.exists?()
  end
end
