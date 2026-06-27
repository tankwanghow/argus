defmodule TugasWeb.UserLive.Login do
  use TugasWeb, :live_view

  alias Tugas.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_standalone flash={@flash}>
      <div class="w-full max-w-sm card bg-base-100 shadow">
        <div class="card-body gap-1">
          <div class="text-center">
            <h1 class="text-lg font-semibold">Log in</h1>
            <p :if={!@current_scope} class="text-sm text-base-content/60 mt-1">
              Don't have an account?
              <.link navigate={~p"/users/register"} class="font-semibold text-primary hover:underline">
                Sign up
              </.link>
            </p>
            <p :if={@current_scope} class="text-sm text-base-content/60 mt-1">
              You need to reauthenticate to perform sensitive actions on your account.
            </p>
          </div>

          <div :if={local_mail_adapter?()} class="alert alert-info text-sm">
            <.icon name="hero-information-circle" class="size-5 shrink-0" />
            <div>
              <p>
                Local mail adapter — visit <.link href="/dev/mailbox" class="underline">mailbox</.link>.
              </p>
            </div>
          </div>

          <.form
            :let={f}
            for={@form}
            id="login_form_magic"
            action={~p"/users/log-in"}
            phx-submit="submit_magic"
          >
            <.input
              readonly={!!@current_scope}
              field={f[:email]}
              type="email"
              label="Email"
              autocomplete="username"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />
            <.button class="btn btn-primary w-full mt-2">
              Log in with email <span aria-hidden="true">→</span>
            </.button>
          </.form>

          <div class="divider text-xs">or</div>

          <.form
            :let={f}
            for={@form}
            id="login_form_password"
            action={~p"/users/log-in"}
            phx-submit="submit_password"
            phx-trigger-action={@trigger_submit}
          >
            <.input
              readonly={!!@current_scope}
              field={f[:identifier]}
              type="text"
              label="Email or username"
              autocomplete="username"
              spellcheck="false"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="current-password"
              spellcheck="false"
            />
            <.button class="btn btn-primary w-full mt-2" name={@form[:remember_me].name} value="true">
              Log in and stay logged in
            </.button>
            <.button class="btn btn-primary btn-soft w-full mt-2">
              Log in only this time
            </.button>
          </.form>
        </div>
      </div>
    </Layouts.mobile_standalone>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    current_email =
      get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    prefill = fn flash_key ->
      Phoenix.Flash.get(socket.assigns.flash, flash_key) || current_email
    end

    form =
      to_form(%{"email" => prefill.(:email), "identifier" => prefill.(:identifier)}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:tugas, Tugas.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
