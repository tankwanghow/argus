defmodule Tugas.Repo do
  use Ecto.Repo,
    otp_app: :tugas,
    adapter: Ecto.Adapters.Postgres
end
