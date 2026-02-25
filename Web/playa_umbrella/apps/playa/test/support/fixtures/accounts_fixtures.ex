defmodule Playa.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Playa.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Playa.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def unique_role_name, do: "Role#{System.unique_integer()}"

  def valid_role_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: unique_role_name(),
      description: "Test role description",
      user_count: 0
    })
  end

  def role_fixture(attrs \\ %{}) do
    {:ok, role} =
      attrs
      |> valid_role_attributes()
      |> Playa.Accounts.create_role()

    role
  end

  def role_user_fixture(role_id, user_id) do
    {:ok, role_user} =
      Playa.Accounts.create_role_user(%{
        role_id: role_id,
        user_id: user_id
      })

    role_user
  end
end
