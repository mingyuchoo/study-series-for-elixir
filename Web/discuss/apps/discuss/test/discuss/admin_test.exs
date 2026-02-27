defmodule Discuss.AdminTest do
  use Discuss.DataCase

  alias Discuss.Admin
  alias Discuss.Admin.User

  import Discuss.AdminFixtures

  describe "list_users/0" do
    test "모든 관리자 사용자를 반환한다" do
      user = admin_user_fixture()
      users = Admin.list_users()
      assert Enum.any?(users, &(&1.id == user.id))
    end
  end

  describe "get_user!/1" do
    test "존재하는 관리자를 반환한다" do
      user = admin_user_fixture()
      fetched = Admin.get_user!(user.id)
      assert fetched.id == user.id
    end

    test "존재하지 않는 ID로 조회하면 에러를 발생시킨다" do
      assert_raise Ecto.NoResultsError, fn ->
        Admin.get_user!(0)
      end
    end
  end

  describe "get_user_by_auth_user_id/1" do
    test "auth_user_id로 관리자를 반환한다" do
      {:ok, auth_user} =
        DiscussAuth.Accounts.register_user(%{
          email: "auth_admin#{System.unique_integer([:positive])}@example.com",
          password: "hello_world!"
        })

      user = admin_user_fixture(%{"auth_user_id" => auth_user.id})
      fetched = Admin.get_user_by_auth_user_id(auth_user.id)
      assert fetched.id == user.id
    end

    test "존재하지 않는 auth_user_id로 nil을 반환한다" do
      refute Admin.get_user_by_auth_user_id(0)
    end
  end

  describe "create_user/1" do
    test "유효한 데이터로 관리자를 생성한다" do
      attrs = valid_admin_user_attributes()
      assert {:ok, %User{} = user} = Admin.create_user(attrs)
      assert user.name == attrs["name"]
      assert user.email == attrs["email"]
      assert user.role == "admin"
    end

    test "유효하지 않은 데이터로 에러를 반환한다" do
      assert {:error, changeset} = Admin.create_user(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "기본 인자로 호출하면 빈 맵을 사용한다" do
      assert {:error, changeset} = Admin.create_user()
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "update_user/2" do
    test "유효한 데이터로 관리자를 업데이트한다" do
      user = admin_user_fixture()
      assert {:ok, updated} = Admin.update_user(user, %{name: "수정된 이름"})
      assert updated.name == "수정된 이름"
    end

    test "유효하지 않은 데이터로 에러를 반환한다" do
      user = admin_user_fixture()
      assert {:error, changeset} = Admin.update_user(user, %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "delete_user/1" do
    test "관리자를 삭제한다" do
      user = admin_user_fixture()
      assert {:ok, _} = Admin.delete_user(user)

      assert_raise Ecto.NoResultsError, fn ->
        Admin.get_user!(user.id)
      end
    end
  end

  describe "change_user/2" do
    test "changeset을 반환한다" do
      user = admin_user_fixture()
      changeset = Admin.change_user(user)
      assert %Ecto.Changeset{} = changeset
    end

    test "속성과 함께 changeset을 반환한다" do
      changeset = Admin.change_user(%User{}, %{name: "새 이름"})
      assert %Ecto.Changeset{} = changeset
    end
  end
end
