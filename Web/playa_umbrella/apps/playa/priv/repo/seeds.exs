# Script for populating the database. You can run it as:
#
#      mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#      Playa.Repo.insert!(%Playa.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Playa.Accounts
alias Playa.Accounts.Role
alias Playa.Repo

# Roles
[
  %{name: "Appr", description: "Apprentice"},
  %{name: "Dev", description: "Developer"},
  %{name: "Op", description: "Operator"},
  %{name: "QA", description: "Quality Assurance"},
  %{name: "Aud", description: "Auditor"},
  %{name: "Admin", description: "Administrator"}
]
|> Enum.each(fn attr ->
  case Repo.get_by(Role, name: attr.name) do
    nil ->
      case Accounts.create_role(attr) do
        {:ok, _role} -> :ok
        {:error, changeset} -> raise "Failed to create role: #{inspect(changeset)}"
      end

    _role ->
      :ok
  end
end)

# Users
[
  %{email: "ghost@email.com", password: "qwe123QWE!@#", nickname: "Ghost", role_id: 1}
]
|> Enum.each(fn attr ->
  case Accounts.get_user_by_email(attr.email) do
    nil ->
      case Accounts.register_user(attr) do
        {:ok, user} ->
          Enum.map(user.roles, fn role -> Accounts.increase_user_count(role) end)

        {:error, changeset} ->
          raise "Failed to register user: #{inspect(changeset)}"
      end

    _user ->
      :ok
  end
end)
