defmodule ArgusWeb.InvitationController do
  use ArgusWeb, :controller

  alias Argus.Accounts
  alias Argus.Entities

  @doc """
  Accepts an invitation. GET-rendered accept page POSTs here with one of:

    * already logged in  -> no extra params; joins the current user
    * create account     -> %{"create" => %{"username", "password", "email"?}}
    * log in to accept   -> %{"login"  => %{"identifier", "password"}}
  """
  def accept(conn, %{"token" => token} = params) do
    with {:ok, invitation} <- Entities.get_invitation_by_encoded_token(token),
         {:ok, user} <- resolve_user(conn, params),
         {:ok, _membership} <- Entities.accept_invitation(user, invitation.token) do
      conn
      |> put_session(:user_return_to, ~p"/entities/#{invitation.entity.slug}")
      |> put_flash(:info, "Welcome to #{invitation.entity.name}!")
      |> ArgusWeb.UserAuth.log_in_user(user)
    else
      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Those credentials didn't match. Try again.")
        |> redirect(to: ~p"/invitations/#{token}")

      {:error, %Ecto.Changeset{}} ->
        # Keep this generic — a field-level "username has already been taken"
        # message would leak which usernames exist (user enumeration).
        conn
        |> put_flash(
          :error,
          "Couldn't create your account — check your username (3+ letters/numbers) and password (12+ characters), then try again."
        )
        |> redirect(to: ~p"/invitations/#{token}")

      {:error, :seat_limit_reached} ->
        conn
        |> put_flash(:error, "That entity is full — ask an admin to free up a seat.")
        |> redirect(to: ~p"/")

      _ ->
        conn
        |> put_flash(:error, "This invitation link is invalid, expired, or already accepted.")
        |> redirect(to: ~p"/")
    end
  end

  def mobile_accept(conn, %{"token" => token} = params) do
    with {:ok, invitation} <- Entities.get_invitation_by_encoded_token(token),
         {:ok, user} <- resolve_user(conn, params),
         {:ok, _membership} <- Entities.accept_invitation(user, invitation.token) do
      conn
      |> put_session(:user_return_to, ~p"/m/#{invitation.entity.slug}")
      |> put_flash(:info, "Welcome to #{invitation.entity.name}!")
      |> ArgusWeb.UserAuth.log_in_user(user)
    else
      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, "Those credentials didn't match. Try again.")
        |> redirect(to: ~p"/m/invitations/#{token}")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(
          :error,
          "Couldn't create your account — check your username (3+ letters/numbers) and password (12+ characters), then try again."
        )
        |> redirect(to: ~p"/m/invitations/#{token}")

      {:error, :seat_limit_reached} ->
        conn
        |> put_flash(:error, "That entity is full — ask an admin to free up a seat.")
        |> redirect(to: ~p"/entities")

      _ ->
        conn
        |> put_flash(:error, "This invitation link is invalid, expired, or already accepted.")
        |> redirect(to: ~p"/")
    end
  end

  defp resolve_user(conn, params) do
    cond do
      scope = conn.assigns[:current_scope] ->
        {:ok, scope.user}

      match?(%{"create" => %{"username" => _, "password" => _}}, params) ->
        Accounts.register_invited_user(params["create"])

      match?(%{"login" => %{"identifier" => _, "password" => _}}, params) ->
        %{"identifier" => id, "password" => pw} = params["login"]

        case Accounts.get_user_by_login_and_password(id, pw) do
          %Accounts.User{} = user -> {:ok, user}
          nil -> {:error, :invalid_credentials}
        end

      true ->
        {:error, :invalid}
    end
  end
end
