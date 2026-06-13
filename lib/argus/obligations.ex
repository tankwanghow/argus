defmodule Argus.Obligations do
  @moduledoc """
  Obligations domain — cycles, events, and workflow.
  """

  import Ecto.Query, warn: false

  alias Argus.Accounts.Scope
  alias Argus.Authorization
  alias Argus.Obligations.{Collaborator, Completion, Event, Obligation, Recurrence, Series, Type}
  alias Argus.Repo

  def live(query \\ Obligation) do
    from(o in query, where: o.status == "active" and is_nil(o.completed_at))
  end

  def list_events(%Obligation{} = obligation) do
    Event
    |> where([e], e.obligation_id == ^obligation.id)
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  def latest_event(%Obligation{} = obligation) do
    Event
    |> where([e], e.obligation_id == ^obligation.id)
    |> order_by([e], [
      desc: e.inserted_at,
      desc:
        fragment(
          "CASE ? WHEN 'done' THEN 4 WHEN 'in_progress' THEN 3 WHEN 'cancelled' THEN 2 WHEN 'open' THEN 1 ELSE 0 END",
          e.status
        )
    ])
    |> limit(1)
    |> Repo.one!()
  end

  def create_obligation(%Scope{} = scope, attrs) do
    with true <- Authorization.can?(scope, :create_obligation),
         {:ok, type} <- fetch_type_for_entity(scope, attrs),
         {:ok, obligation} <- insert_obligation(scope, attrs, type) do
      {:ok, obligation}
    else
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def start_progress(%Scope{} = scope, %Obligation{} = obligation) do
    obligation = Repo.preload(obligation, :collaborators)

    with true <- Authorization.can?(scope, :start_progress, obligation),
         :ok <- ensure_latest_open(obligation),
         {:ok, event} <- insert_progress_event(scope, obligation) do
      {:ok, event}
    else
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def complete(%Scope{} = scope, %Obligation{} = obligation, attrs) do
    obligation = Repo.preload(obligation, [:collaborators, :obligation_type])

    with true <- Authorization.can?(scope, :mark_done, obligation),
         :ok <- Completion.validate_done_requirements(obligation, attrs, []),
         :ok <- validate_next_due(obligation, attrs),
         {:ok, completed, spawned} <- complete_multi(scope, obligation, attrs) do
      {:ok, completed, spawned}
    else
      false -> :not_authorise
      {:error, _} = error -> error
    end
  end

  def cancel_obligation(%Scope{} = scope, %Obligation{} = obligation, attrs) do
    note = Map.get(attrs, :note) || Map.get(attrs, "note")

    with true <- Authorization.can?(scope, :cancel_obligation) do
      now = DateTime.utc_now(:second)

      Ecto.Multi.new()
      |> Ecto.Multi.update_all(
        :obligation,
        live(Obligation) |> where([o], o.id == ^obligation.id),
        set: [status: "cancelled", updated_at: now]
      )
      |> Ecto.Multi.run(:check, fn _repo, %{obligation: {count, _}} ->
        if count == 1, do: {:ok, :updated}, else: {:error, :not_live}
      end)
      |> Ecto.Multi.insert(:cancelled_event, fn _ ->
        %Event{
          obligation_id: obligation.id,
          status_by_id: scope.user.id
        }
        |> Event.changeset(%{status: "cancelled", note: note})
      end)
      |> Repo.transaction()
      |> case do
        {:ok, _} ->
          {:ok, Repo.get!(Obligation, obligation.id)}

        {:error, :check, :not_live, _} ->
          {:error, :not_live}

        {:error, :cancelled_event, changeset, _} ->
          {:error, changeset}
      end
    else
      false -> :not_authorise
    end
  end

  def end_series(%Scope{} = scope, %Obligation{} = obligation, _attrs) do
    with true <- Authorization.can?(scope, :end_series) do
      now = DateTime.utc_now(:second)

      Ecto.Multi.new()
      |> Ecto.Multi.update_all(
        :obligation,
        live(Obligation) |> where([o], o.id == ^obligation.id),
        set: [status: "cancelled", series_ended_at: now, updated_at: now]
      )
      |> Ecto.Multi.run(:check, fn _repo, %{obligation: {count, _}} ->
        if count == 1, do: {:ok, :updated}, else: {:error, :not_live}
      end)
      |> Ecto.Multi.insert(:cancelled_event, fn _ ->
        %Event{
          obligation_id: obligation.id,
          status_by_id: scope.user.id
        }
        |> Event.changeset(%{status: "cancelled"})
      end)
      |> Repo.transaction()
      |> case do
        {:ok, _} ->
          {:ok, Repo.get!(Obligation, obligation.id)}

        {:error, :check, :not_live, _} ->
          {:error, :not_live}

        {:error, :cancelled_event, changeset, _} ->
          {:error, changeset}
      end
    else
      false -> :not_authorise
    end
  end

  defp complete_multi(scope, obligation, attrs) do
    now = DateTime.utc_now(:second)
    next_due_by = Map.get(attrs, :next_due_by) || Map.get(attrs, "next_due_by")
    note = Map.get(attrs, :note) || Map.get(attrs, "note")
    spawn? = should_spawn_next?(obligation, next_due_by)

    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :close,
      live(Obligation) |> where([o], o.id == ^obligation.id),
      set: [completed_at: now, updated_at: now]
    )
    |> Ecto.Multi.run(:check_live, fn _repo, %{close: {count, _}} ->
      if count == 1, do: {:ok, :closed}, else: {:error, :not_live}
    end)
    |> Ecto.Multi.insert(:done_event, fn _ ->
      %Event{
        obligation_id: obligation.id,
        status_by_id: scope.user.id
      }
      |> Event.changeset(%{status: "done", note: note})
    end)
    |> Ecto.Multi.run(:spawn, fn repo, %{close: {_, _}} ->
      if spawn? do
        case spawn_next_cycle(repo, obligation, next_due_by) do
          {:ok, new_obligation} -> {:ok, new_obligation}
          {:error, reason} -> {:error, reason}
        end
      else
        {:ok, nil}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{spawn: new_obligation}} ->
        {:ok, Repo.get!(Obligation, obligation.id), new_obligation}

      {:error, :check_live, :not_live, _} ->
        {:error, :not_live}

      {:error, :spawn, :not_live, _} ->
        {:error, :not_live}

      {:error, :done_event, changeset, _} ->
        {:error, changeset}
    end
  end

  defp should_spawn_next?(%Obligation{} = obligation, next_due_by) do
    Recurrence.recurring?(obligation.obligation_type) and not Series.ended?(obligation.series_id) and
      not is_nil(next_due_by)
  end

  defp validate_next_due(%Obligation{} = obligation, attrs) do
    next_due_by = Map.get(attrs, :next_due_by) || Map.get(attrs, "next_due_by")
    type = obligation.obligation_type || Repo.get!(Type, obligation.obligation_type_id)

    if Recurrence.recurring?(type) and not Series.ended?(obligation.series_id) and
         next_due_by in [nil, ""] do
      {:error, :next_due_required}
    else
      :ok
    end
  end

  defp spawn_next_cycle(repo, %Obligation{} = done_obligation, next_due_by) do
    type = Repo.get!(Type, done_obligation.obligation_type_id)
    collaborators = Repo.all(from c in Collaborator, where: c.obligation_id == ^done_obligation.id)
    now = DateTime.utc_now(:second)

    obligation_changeset =
      %Obligation{
        entity_id: done_obligation.entity_id,
        series_id: done_obligation.series_id,
        status: "active",
        complete_note_required: type.complete_note_required,
        complete_documents: type.complete_documents
      }
      |> Obligation.changeset(%{
        title: done_obligation.title,
        obligation_type_id: done_obligation.obligation_type_id,
        primary_assignee_id: done_obligation.primary_assignee_id,
        due_by: next_due_by
      })

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:obligation, obligation_changeset)
    |> Ecto.Multi.insert_all(:collaborators, Collaborator, fn %{obligation: obligation} ->
      Enum.map(collaborators, fn c ->
        %{
          id: Ecto.UUID.generate(),
          obligation_id: obligation.id,
          user_id: c.user_id,
          inserted_at: now
        }
      end)
    end)
    |> Ecto.Multi.insert(:open_event, fn %{obligation: obligation} ->
      %Event{
        obligation_id: obligation.id,
        status_by_id: done_obligation.primary_assignee_id
      }
      |> Event.changeset(%{status: "open"})
    end)
    |> repo.transaction()
    |> case do
      {:ok, %{obligation: obligation}} -> {:ok, obligation}
      {:error, :obligation, %Ecto.Changeset{errors: errors}, _} ->
        if constraint_error?(errors, :series_id), do: {:error, :not_live}, else: {:error, :invalid}

      {:error, _, reason, _} ->
        {:error, reason}
    end
  end

  defp constraint_error?(errors, field) do
    Enum.any?(errors, fn
      {^field, {_msg, [constraint: :unique, constraint_name: _]}} -> true
      _ -> false
    end)
  end

  defp ensure_latest_open(%Obligation{} = obligation) do
    forward_step? =
      Event
      |> where([e], e.obligation_id == ^obligation.id and e.status != "open")
      |> Repo.exists?()

    if forward_step?, do: {:error, :not_open}, else: :ok
  end

  defp insert_progress_event(%Scope{user: user}, %Obligation{} = obligation) do
    %Event{
      obligation_id: obligation.id,
      status_by_id: user.id
    }
    |> Event.changeset(%{status: "in_progress"})
    |> Repo.insert()
  end

  defp fetch_type_for_entity(%Scope{entity: entity}, attrs) do
    type_id = Map.get(attrs, :obligation_type_id) || Map.get(attrs, "obligation_type_id")

    case Repo.get(Type, type_id) do
      %Type{entity_id: nil} = type -> {:ok, type}
      %Type{entity_id: entity_id} = type when entity_id == entity.id -> {:ok, type}
      %Type{} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  defp insert_obligation(%Scope{user: user, entity: entity}, attrs, %Type{} = type) do
    series_id = Ecto.UUID.generate()
    open_note = Map.get(attrs, :open_note) || Map.get(attrs, "open_note")
    collaborator_ids = Map.get(attrs, :collaborator_ids, []) || Map.get(attrs, "collaborator_ids", [])

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:obligation, fn _ ->
      %Obligation{
        entity_id: entity.id,
        series_id: series_id,
        status: "active",
        complete_note_required: type.complete_note_required,
        complete_documents: type.complete_documents
      }
      |> Obligation.changeset(attrs)
    end)
    |> maybe_insert_collaborators(collaborator_ids)
    |> Ecto.Multi.insert(:open_event, fn %{obligation: obligation} ->
      %Event{
        obligation_id: obligation.id,
        status_by_id: user.id
      }
      |> Event.changeset(%{status: "open", note: open_note})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{obligation: obligation}} -> {:ok, obligation}
      {:error, :obligation, changeset, _} -> {:error, changeset}
      {:error, :open_event, changeset, _} -> {:error, changeset}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  defp maybe_insert_collaborators(multi, []), do: multi

  defp maybe_insert_collaborators(multi, collaborator_ids) do
    Ecto.Multi.insert_all(multi, :collaborators, Collaborator, fn %{obligation: obligation} ->
      now = DateTime.utc_now(:second)

      Enum.map(collaborator_ids, fn user_id ->
        %{
          id: Ecto.UUID.generate(),
          obligation_id: obligation.id,
          user_id: user_id,
          inserted_at: now
        }
      end)
    end)
  end
end