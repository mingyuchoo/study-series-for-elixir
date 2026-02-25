defmodule Playa.AccountsTest do
  use Playa.DataCase

  alias Playa.Accounts

  import Playa.AccountsFixtures
  alias Playa.Accounts.User

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid", password: "not valid"})

      assert %{
               email: ["must have the @ sign and no spaces"],
               password: ["should be at least 12 character(s)"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long, password: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users with a hashed password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "list_users/0" do
    test "returns all users with their roles preloaded" do
      user1 = user_fixture()
      user2 = user_fixture()

      users = Accounts.list_users()
      user_ids = Enum.map(users, & &1.id)

      assert user1.id in user_ids
      assert user2.id in user_ids
      assert length(users) >= 2

      # Verify roles are preloaded
      first_user = List.first(users)
      assert Ecto.assoc_loaded?(first_user.roles)
    end
  end

  describe "update_user/2" do
    test "updates the user with valid attributes" do
      user = user_fixture()
      new_email = unique_user_email()

      assert {:ok, updated_user} =
               Accounts.update_user(user, %{email: new_email, password: valid_user_password()})

      assert updated_user.email == new_email
      assert Ecto.assoc_loaded?(updated_user.roles)
    end

    test "returns error changeset with invalid attributes" do
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.update_user(user, %{email: "invalid", password: valid_user_password()})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end
  end

  describe "delete_user/1" do
    test "deletes the user" do
      user = user_fixture()
      assert {:ok, _deleted_user} = Accounts.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(user.id) end
    end
  end

  describe "Roles" do
    test "list_roles/0 returns all roles" do
      role1 = role_fixture()
      role2 = role_fixture()

      roles = Accounts.list_roles()
      role_ids = Enum.map(roles, & &1.id)

      assert role1.id in role_ids
      assert role2.id in role_ids
    end

    test "get_role!/1 returns the role with given id" do
      role = role_fixture()
      fetched_role = Accounts.get_role!(role.id)

      assert fetched_role.id == role.id
      assert fetched_role.name == role.name
      assert Ecto.assoc_loaded?(fetched_role.users)
    end

    test "create_role/1 with valid data creates a role" do
      role_name = unique_role_name()
      valid_attrs = %{name: role_name, description: "Administrator role", user_count: 0}

      assert {:ok, role} = Accounts.create_role(valid_attrs)
      assert role.name == role_name
      assert role.description == "Administrator role"
      assert role.user_count == 0
      assert Ecto.assoc_loaded?(role.users)
    end

    test "create_role/1 with invalid data returns error changeset" do
      assert {:error, changeset} = Accounts.create_role(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "update_role/2 with valid data updates the role" do
      role = role_fixture()
      update_attrs = %{name: "UpdatedRole", description: "Updated description"}

      assert {:ok, updated_role} = Accounts.update_role(role, update_attrs)
      assert updated_role.name == "UpdatedRole"
      assert updated_role.description == "Updated description"
    end

    test "delete_role/1 deletes the role" do
      role = role_fixture()
      assert {:ok, _deleted_role} = Accounts.delete_role(role)
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_role!(role.id) end
    end
  end

  describe "RoleUser associations" do
    test "create_role_user/1 creates association between role and user" do
      role = role_fixture()
      user = user_fixture()

      assert {:ok, role_user} = Accounts.create_role_user(%{role_id: role.id, user_id: user.id})
      assert role_user.role_id == role.id
      assert role_user.user_id == user.id
    end

    test "get_role_user/2 returns the role_user association" do
      role = role_fixture()
      user = user_fixture()
      {:ok, role_user} = Accounts.create_role_user(%{role_id: role.id, user_id: user.id})

      fetched = Accounts.get_role_user(role.id, user.id)
      assert fetched.id == role_user.id
    end

    test "list_role_user_by_user_id/1 returns all roles for a user" do
      user = user_fixture()
      role1 = role_fixture()
      role2 = role_fixture()

      {:ok, role_user1} = Accounts.create_role_user(%{role_id: role1.id, user_id: user.id})
      {:ok, role_user2} = Accounts.create_role_user(%{role_id: role2.id, user_id: user.id})

      role_users = Accounts.list_role_user_by_user_id(user.id)
      role_user_ids = Enum.map(role_users, & &1.id)

      # User has default role + role1 + role2, so check if our created roles are present
      assert role_user1.id in role_user_ids
      assert role_user2.id in role_user_ids
      assert length(role_users) >= 2
    end

    test "delete_role_user/1 removes association" do
      role = role_fixture()
      user = user_fixture()
      {:ok, role_user} = Accounts.create_role_user(%{role_id: role.id, user_id: user.id})

      assert {:ok, _deleted} = Accounts.delete_role_user(role_user)
      assert is_nil(Accounts.get_role_user(role.id, user.id))
    end
  end

  describe "Session tokens" do
    test "generate_user_session_token/1 generates a token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert is_binary(token)
    end

    test "get_user_by_session_token/1 returns user for valid token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      fetched_user = Accounts.get_user_by_session_token(token)
      assert fetched_user.id == user.id
    end

    test "get_user_by_session_token/1 returns nil for invalid token" do
      assert is_nil(Accounts.get_user_by_session_token("invalid_token"))
    end

    test "delete_user_session_token/1 deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert :ok = Accounts.delete_user_session_token(token)
      assert is_nil(Accounts.get_user_by_session_token(token))
    end
  end

  describe "is_admin?/1" do
    test "returns true when user has Admin role" do
      # Create or get existing Admin role to avoid unique constraint
      admin_role =
        case Accounts.create_role(%{name: "Admin", description: "Administrator", user_count: 0}) do
          {:ok, role} -> role
          {:error, _} -> Accounts.list_roles() |> Enum.find(&(&1.name == "Admin"))
        end

      user = user_fixture()
      Accounts.create_role_user(%{role_id: admin_role.id, user_id: user.id})

      user_with_roles = Accounts.get_user!(user.id)
      assert Accounts.is_admin?(user_with_roles)
    end

    test "returns false when user does not have Admin role" do
      role = role_fixture()
      user = user_fixture()
      Accounts.create_role_user(%{role_id: role.id, user_id: user.id})

      user_with_roles = Accounts.get_user!(user.id)
      refute Accounts.is_admin?(user_with_roles)
    end
  end
end
