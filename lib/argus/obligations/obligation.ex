defmodule Argus.Obligations.Obligation do
  @moduledoc """
  Obligation cycle. Full schema lands in Task 8; struct exists early for authorization.
  """
  defstruct [:id, :primary_assignee_id, :collaborators]
end