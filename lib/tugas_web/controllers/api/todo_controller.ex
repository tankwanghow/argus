defmodule TugasWeb.Api.TodoController do
  use TugasWeb, :controller

  alias Tugas.{Entities, Todos}
  alias Tugas.Accounts.Scope

  def create(conn, %{"slug" => slug, "title" => title}) do
    scope = conn.assigns.current_scope
    user = scope.user

    with entity when not is_nil(entity) <- safe_entity(slug, user),
         true <- entity.id == conn.assigns.api_token_entity_id,
         membership <- Entities.get_membership!(user, entity),
         true <- active?(membership),
         {:ok, todo} <-
           Todos.create_todo(Scope.put_entity(scope, entity, membership), %{"title" => title}) do
      conn |> put_status(:created) |> json(%{id: todo.id})
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: errors(changeset)})

      _ ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})
    end
  end

  def create(conn, _params) do
    conn |> put_status(:unprocessable_entity) |> json(%{errors: %{title: ["is required"]}})
  end

  defp safe_entity(slug, user) do
    Entities.get_entity_by_slug_for_user!(slug, user)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp active?(membership),
    do: not is_nil(membership.accepted_at) and is_nil(membership.disabled_at)

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end
end
