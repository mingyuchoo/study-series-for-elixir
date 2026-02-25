defmodule Productivity.AccountFixtures do
  @moduledoc """
  This module defines test helpers for creating
  user entities for productivity tests.

  Since Productivity needs to reference users from the playa schema,
  we create users using Productivity.Repo to ensure they're visible
  in the same database connection.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: unique_user_email(),
        username: "user#{System.unique_integer()}",
        role: :user,
        password: "hello world!"
      })
      |> then(fn user_attrs ->
        # Insert directly into playa schema using Productivity.Repo
        Productivity.Repo.insert(
          %Playa.Accounts.User{}
          |> Playa.Accounts.User.registration_changeset(user_attrs),
          prefix: "playa"
        )
      end)

    user
  end
end
