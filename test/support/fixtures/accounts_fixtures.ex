defmodule Tugas.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Tugas.Accounts` context.
  """

  import Ecto.Query

  alias Tugas.Accounts
  alias Tugas.Accounts.Scope

  # `System.unique_integer/1` only guarantees uniqueness within a single runtime
  # instance — its counter resets every `mix test` run. The test DB persists across
  # runs (it is created/migrated, never dropped), so a value generated this run can
  # collide with a row a previous run left behind, failing `unsafe_validate_unique`
  # intermittently. A random suffix makes these globally unique across runs too.
  def unique_user_email, do: "user#{unique_suffix()}@example.com"
  def valid_user_password, do: "hello world!"

  def unique_username, do: "user#{unique_suffix()}"

  # Underscore separator (not "-") so the suffix is valid for usernames too, which
  # only allow letters, numbers, and underscores.
  defp unique_suffix do
    "#{System.unique_integer([:positive])}_#{:rand.uniform(1_000_000_000)}"
  end

  def username_user_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        username: unique_username(),
        password: valid_user_password()
      })

    {:ok, user} = Tugas.Accounts.register_invited_user(attrs)
    user
  end

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Tugas.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Tugas.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Tugas.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
