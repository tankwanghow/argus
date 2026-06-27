defmodule TugasWeb.DocumentController do
  use TugasWeb, :controller

  alias Tugas.Accounts.Scope
  alias Tugas.Entities
  alias Tugas.Obligations
  alias Tugas.Obligations.{Event, EventDocument, Obligation}
  alias Tugas.Repo
  alias Tugas.Uploads
  alias Tugas.Uploads.{FileKind, Limits}
  alias TugasWeb.ObligationLive.DocumentHelpers

  import Ecto.Query

  @doc """
  Plain multipart upload of a document. Used by the `UploadDirect` client hook
  instead of LiveView's socket upload: a normal HTTP request does not depend on
  the live socket, so backgrounding the page during a long camera capture no
  longer loses the file (the socket-upload path dropped it on the resulting
  LiveView remount). Size limits are enforced server-side here, authoritatively.
  """
  def create(conn, %{"entity_slug" => slug, "obligation_id" => obligation_id} = params) do
    scope = entity_scope!(conn, slug)
    obligation = Obligations.get_obligation!(scope, obligation_id)

    upload = params["file"]
    document_slot = blank_to_nil(params["document_slot"])
    event = resolve_event(obligation, params["event_id"])

    with %Plug.Upload{path: path, filename: filename, content_type: content_type} = upload <-
           upload,
         %Event{} = event <- event,
         size when is_integer(size) <- file_size(path),
         :ok <- Limits.validate_size(filename, size, content_type) do
      case Obligations.add_document(scope, obligation, event, upload, document_slot) do
        {:ok, document} ->
          json(conn, %{ok: true, id: document.id})

        :not_authorise ->
          error_json(conn, 403, "Not authorized.")

        {:error, :file_too_large} ->
          kind = FileKind.classify(filename, content_type)

          error_json(
            conn,
            413,
            Limits.too_large_message(kind, Limits.limit_bytes(filename, content_type))
          )

        {:error, :invalid_slot} ->
          error_json(conn, 422, "That document slot is not required for this obligation.")

        {:error, :slot_taken} ->
          error_json(
            conn,
            409,
            "This slot already has a file. Delete or void it before uploading again."
          )

        {:error, :not_workable} ->
          error_json(conn, 422, "This step is no longer open for uploads.")

        {:error, :not_found} ->
          error_json(conn, 404, "Step not found.")

        {:error, :invalid_size} ->
          error_json(conn, 422, "Could not read uploaded file.")

        {:error, _} ->
          error_json(conn, 422, "Could not add document.")
      end
    else
      {:error, message} when is_binary(message) -> error_json(conn, 413, message)
      {:error, :invalid_size} -> error_json(conn, 422, "Could not read uploaded file.")
      nil -> error_json(conn, 422, "No step available to attach documents to.")
      _ -> error_json(conn, 400, "Choose a file to upload.")
    end
  end

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

  defp entity_scope!(conn, slug) do
    user = conn.assigns.current_scope.user
    entity = Entities.get_entity_by_slug_for_user!(slug, user)
    membership = Entities.get_membership!(user, entity)
    Scope.put_entity(conn.assigns.current_scope, entity, membership)
  end

  defp resolve_event(obligation, id) when id in [nil, ""] do
    DocumentHelpers.upload_event(obligation.events)
  end

  defp resolve_event(obligation, id) do
    Enum.find(obligation.events, &(to_string(&1.id) == to_string(id)))
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> {:error, :invalid_size}
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp error_json(conn, status, message) do
    conn |> put_status(status) |> json(%{ok: false, error: message})
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
