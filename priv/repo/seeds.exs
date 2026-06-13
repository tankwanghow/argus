# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias Argus.Obligations.Type
alias Argus.Repo

presets = [
  %{
    name: "EPF Monthly",
    recurring_interval: "monthly",
    complete_documents: "payment_receipt",
    reminder_offsets: "7,1"
  },
  %{
    name: "SOCSO Monthly",
    recurring_interval: "monthly",
    reminder_offsets: "7,1"
  },
  %{
    name: "SST Return",
    recurring_interval: "quarterly",
    reminder_offsets: "30,7,1"
  },
  %{
    name: "SSM Annual Return",
    recurring_interval: "annual",
    reminder_offsets: "30,7,1"
  },
  %{
    name: "LHDN Tax Estimation",
    recurring_interval: "custom",
    reminder_offsets: "30,7,1"
  }
]

for attrs <- presets do
  %Type{entity_id: nil}
  |> Type.changeset(attrs)
  |> Repo.insert!(
    on_conflict: :nothing,
    conflict_target: [:entity_id, :name]
  )
end