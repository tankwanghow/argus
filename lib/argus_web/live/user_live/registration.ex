defmodule ArgusWeb.UserLive.Registration do
  use ArgusWeb, :live_view

  alias Argus.Accounts
  alias Argus.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_standalone flash={@flash}>
      <div class="w-full max-w-sm card bg-base-100 shadow">
        <div class="card-body gap-4">
          <div class="text-center">
            <h1 class="text-lg font-semibold">Register for an account</h1>
            <p class="text-sm text-base-content/60 mt-1">
              Already registered?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-primary hover:underline">
                Log in
              </.link>
            </p>
          </div>

          <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
            <.input
              field={@form[:email]}
              type="email"
              label="Email"
              autocomplete="username"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />

            <.button phx-disable-with="Creating account..." class="btn btn-primary w-full mt-2">
              Create an account
            </.button>
          </.form>
        </div>
      </div>
    </Layouts.mobile_standalone>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: ArgusWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "An email was sent to #{user.email}, please access it to confirm your account."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
