defmodule Tugas.Authorization do
  @moduledoc """
  Scope-first authorization. Keys off `scope.role` — never re-queries the DB.
  """

  alias Tugas.Accounts.Scope
  alias Tugas.Duties.Duty

  @todo_actions [
    :view_todos,
    :create_todo,
    :edit_todo,
    :complete_todo,
    :delete_todo,
    :cancel_todo
  ]

  def can?(%Scope{role: :admin}, :manage_entity), do: true
  def can?(%Scope{role: :admin}, _action), do: true

  def can?(%Scope{role: :manager}, :manage_types), do: true
  def can?(%Scope{role: :manager}, :create_duty), do: true
  def can?(%Scope{role: :manager}, :edit_duty), do: true
  def can?(%Scope{role: :manager}, :skip), do: true
  def can?(%Scope{role: :manager}, :end_series), do: true
  def can?(%Scope{role: :manager}, :void_document), do: true
  def can?(%Scope{role: :manager}, :mark_completed_in_error), do: true
  def can?(%Scope{role: :manager}, :manage_entity), do: false
  def can?(%Scope{role: :manager}, action) when action in @todo_actions, do: true
  def can?(%Scope{role: :manager}, _), do: false

  def can?(%Scope{role: :member}, :manage_entity), do: false
  def can?(%Scope{role: :member}, action) when action in @todo_actions, do: true
  def can?(%Scope{}, _), do: false

  def can?(%Scope{role: :admin}, _action, _duty), do: true

  def can?(%Scope{role: :manager}, :mark_done, _duty), do: true
  def can?(%Scope{role: :manager}, :start_progress, _duty), do: true
  def can?(%Scope{role: :manager}, _, _duty), do: false

  def can?(%Scope{role: :member, user: user}, :mark_done, %Duty{} = duty) do
    not is_nil(duty.primary_assignee_id) and duty.primary_assignee_id == user.id
  end

  def can?(%Scope{role: :member, user: user}, :start_progress, %Duty{} = duty) do
    (not is_nil(duty.primary_assignee_id) and duty.primary_assignee_id == user.id) or
      user.id in collaborator_user_ids(duty)
  end

  def can?(%Scope{}, _, _duty), do: false

  defp collaborator_user_ids(%Duty{collaborators: collaborators})
       when is_list(collaborators) do
    Enum.map(collaborators, & &1.user_id)
  end

  defp collaborator_user_ids(_), do: []
end
