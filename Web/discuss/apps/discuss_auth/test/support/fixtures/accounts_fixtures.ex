defmodule DiscussAuth.AccountsFixtures do
  @moduledoc """
  Accounts 컨텍스트용 테스트 픽스처.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello_world!"

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
      |> DiscussAuth.Accounts.register_user()

    user
  end
end
