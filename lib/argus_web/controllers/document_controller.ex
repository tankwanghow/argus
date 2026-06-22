defmodule ArgusWeb.DocumentController do
  use ArgusWeb, :controller

  alias Argus.Entities
  alias Argus.Obligations.{Event, EventDocument, Obligation}
  alias Argus.Repo
  alias Argus.Uploads

  import Ecto.Query

  def show(conn, %{"entity_slug" => slug, "obligation_id" => obligation_id, "id" => id} = params) do
    user = conn.assigns.current_scope.user
    entity = Entities.get_entity_by_slug_for_user!(slug, user)
    obligation = get_obligation!(obligation_id, entity.id)
    document = get_document!(id, obligation.id)

    # Inline by default so previews can embed the file; ?download=1 forces a "Save as".
    disposition = if params["download"] in ~w(1 true), do: :attachment, else: :inline

    if File.exists?(Uploads.path(document)) do
      send_download(conn, {:file, Uploads.path(document)},
        filename: original_filename(document),
        disposition: disposition
      )
    else
      conn |> put_status(:not_found) |> text("Not found")
    end
  end

  defp get_obligation!(id, entity_id) do
    case Repo.get_by(Obligation, id: id, entity_id: entity_id) do
      %Obligation{} = obligation -> obligation
      nil -> raise Ecto.NoResultsError, queryable: Obligation
    end
  end

  defp get_document!(id, obligation_id) do
    EventDocument
    |> join(:inner, [d], e in Event, on: d.obligation_event_id == e.id)
    |> where([d, e], d.id == ^id and e.obligation_id == ^obligation_id)
    |> Repo.one!()
  end

  defp original_filename(%EventDocument{file: file}) when is_map(file) do
    Map.get(file, "original") || Map.get(file, :original) || "document"
  end
end
