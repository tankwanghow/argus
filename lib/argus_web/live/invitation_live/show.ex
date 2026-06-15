defmodule ArgusWeb.InvitationLive.Show do
  use ArgusWeb, :live_view

  alias Argus.Entities

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-md">
        <%= if @invitation do %>
          <.header>
            Join {@invitation.entity.name}
            <:subtitle>You've been invited as <b>{@invitation.role}</b>.</:subtitle>
          </.header>

          <%= if @current_scope do %>
            <.form for={@accept_form} id="accept-form" action={~p"/invitations/#{@token}/accept"} class="mt-6">
              <.button class="btn btn-primary w-full" phx-disable-with="Joining...">
                Accept invitation
              </.button>
            </.form>
          <% else %>
            <.form for={@create_form} id="create-form" action={~p"/invitations/#{@token}/accept"} class="mt-6 space-y-2">
              <p class="font-semibold">New here? Create your login</p>
              <.input field={@create_form[:username]} label="Username" autocomplete="username" spellcheck="false" phx-mounted={JS.focus()} required />
              <.input field={@create_form[:password]} type="password" label="Password" autocomplete="new-password" required />
              <.input field={@create_form[:email]} type="email" label="Email (optional)" autocomplete="email" spellcheck="false" />
              <.button class="btn btn-primary w-full" phx-disable-with="Creating...">
                Create account & join
              </.button>
            </.form>

            <div class="divider">or</div>

            <.form for={@login_form} id="login-form" action={~p"/invitations/#{@token}/accept"} class="space-y-2">
              <p class="font-semibold">Already have an account?</p>
              <.input field={@login_form[:identifier]} label="Username or email" autocomplete="username" spellcheck="false" required />
              <.input field={@login_form[:password]} type="password" label="Password" autocomplete="current-password" required />
              <.button class="btn btn-primary btn-soft w-full" phx-disable-with="Joining...">
                Log in & join
              </.button>
            </.form>
          <% end %>
        <% else %>
          <.header>Invitation not valid</.header>
          <p class="mt-4 text-center text-base-content/70">
            This invitation link is invalid, expired, or already accepted.
          </p>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    invitation =
      case Entities.get_invitation_by_encoded_token(token) do
        {:ok, invitation} -> invitation
        :error -> nil
      end

    {:ok,
     assign(socket,
       token: token,
       invitation: invitation,
       accept_form: to_form(%{}, as: "accept"),
       create_form: to_form(%{}, as: "create"),
       login_form: to_form(%{}, as: "login")
     )}
  end
end
