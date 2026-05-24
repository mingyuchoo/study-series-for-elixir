defmodule AgenticAiAgent.AccountsTest do
  use AgenticAiAgent.DataCase, async: false

  alias AgenticAiAgent.Accounts

  test "create_user stores a password hash and authenticates" do
    assert {:ok, user} =
             Accounts.create_user(%{
               email: "Ada@example.com",
               display_name: "Ada",
               password: "password123"
             })

    assert user.email == "ada@example.com"
    assert user.preferred_locale == "en"
    assert user.preferred_theme == "system"
    refute user.password_hash == "password123"
    assert {:ok, auth_user} = Accounts.authenticate_user("ada@example.com", "password123")
    assert auth_user.id == user.id

    assert {:error, :invalid_credentials} =
             Accounts.authenticate_user("ada@example.com", "wrongpass")
  end
end
