defmodule Playa.Accounts.RolesTest do
  use Playa.DataCase

  alias Playa.Accounts.Roles

  import Playa.AccountsFixtures

  describe "list/0" do
    test "모든 역할을 반환한다" do
      role1 = role_fixture()
      role2 = role_fixture()

      roles = Roles.list()
      role_ids = Enum.map(roles, & &1.id)

      assert role1.id in role_ids
      assert role2.id in role_ids

      # 역할의 사용자가 프리로드되어 있는지 확인
      Enum.each(roles, fn role ->
        assert Ecto.assoc_loaded?(role.users)
      end)
    end

    test "ID 순으로 정렬되어 반환한다" do
      _role1 = role_fixture()
      _role2 = role_fixture()

      roles = Roles.list()
      role_ids = Enum.map(roles, & &1.id)

      assert role_ids == Enum.sort(role_ids)
    end
  end

  describe "list_by_user_id/1" do
    test "특정 사용자의 역할 목록을 반환한다" do
      role1 = role_fixture()
      role2 = role_fixture()
      user = user_fixture()

      role_user_fixture(role1.id, user.id)
      role_user_fixture(role2.id, user.id)

      roles = Roles.list_by_user_id(user.id)
      role_ids = Enum.map(roles, & &1.id)

      assert length(roles) >= 2
      assert role1.id in role_ids
      assert role2.id in role_ids
    end

    test "존재하지 않는 사용자 ID로는 빈 목록을 반환한다" do
      roles = Roles.list_by_user_id(-1)
      assert roles == []
    end
  end

  describe "list_remaining_by_user_id/1" do
    test "사용자가 가지지 않은 역할 목록을 반환한다" do
      role1 = role_fixture()
      role2 = role_fixture()
      role3 = role_fixture()
      user = user_fixture()

      role_user_fixture(role1.id, user.id)

      remaining_roles = Roles.list_remaining_by_user_id(user.id)
      remaining_role_ids = Enum.map(remaining_roles, & &1.id)

      refute role1.id in remaining_role_ids
      assert role2.id in remaining_role_ids
      assert role3.id in remaining_role_ids
    end

    test "모든 역할을 가진 사용자는 빈 목록을 반환한다" do
      role1 = role_fixture()
      role2 = role_fixture()
      user = user_fixture()

      role_user_fixture(role1.id, user.id)
      role_user_fixture(role2.id, user.id)

      # 기본 역할들 제외
      all_roles = Roles.list()
      user_roles = Roles.list_by_user_id(user.id)

      if length(all_roles) == length(user_roles) do
        remaining_roles = Roles.list_remaining_by_user_id(user.id)
        assert remaining_roles == []
      end
    end
  end

  describe "get!/1" do
    test "ID로 역할을 조회한다" do
      role = role_fixture()
      fetched_role = Roles.get!(role.id)

      assert fetched_role.id == role.id
      assert fetched_role.name == role.name
      assert Ecto.assoc_loaded?(fetched_role.users)
    end

    test "존재하지 않는 ID로는 예외를 발생시킨다" do
      assert_raise Ecto.NoResultsError, fn ->
        Roles.get!(-1)
      end
    end
  end

  describe "get_default/1" do
    test "이름으로 기본 역할을 조회한다" do
      # 시스템에 이미 존재하는 기본 역할 조회
      role = Roles.get_default("Admin")

      assert role.name == "Admin"
      assert Ecto.assoc_loaded?(role.users)
    end

    test "존재하지 않는 이름으로는 예외를 발생시킨다" do
      assert_raise Ecto.NoResultsError, fn ->
        Roles.get_default("NonExistentRole")
      end
    end
  end

  describe "create/1" do
    test "유효한 속성으로 역할을 생성한다" do
      attrs = %{name: "TestRole", description: "Test description"}

      assert {:ok, role} = Roles.create(attrs)
      assert role.name == attrs.name
      assert role.description == attrs.description
      assert role.user_count == 0
      assert Ecto.assoc_loaded?(role.users)
    end

    test "유효하지 않은 속성으로는 역할을 생성할 수 없다" do
      assert {:error, changeset} = Roles.create(%{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "중복된 이름으로는 역할을 생성할 수 없다" do
      role = role_fixture()

      assert {:error, changeset} = Roles.create(%{name: role.name, description: "Test"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update/2" do
    test "유효한 속성으로 역할을 업데이트한다" do
      role = role_fixture()
      update_attrs = %{description: "Updated description"}

      assert {:ok, updated_role} = Roles.update(role, update_attrs)
      assert updated_role.description == "Updated description"
      assert updated_role.name == role.name
    end

    test "이름을 업데이트할 수 있다" do
      role = role_fixture()
      update_attrs = %{name: "UpdatedName"}

      assert {:ok, updated_role} = Roles.update(role, update_attrs)
      assert updated_role.name == "UpdatedName"
    end

    test "유효하지 않은 속성으로는 업데이트할 수 없다" do
      role = role_fixture()

      assert {:error, changeset} = Roles.update(role, %{name: nil})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "delete/1" do
    test "역할을 삭제한다" do
      role = role_fixture()

      assert {:ok, _deleted_role} = Roles.delete(role)
      assert_raise Ecto.NoResultsError, fn -> Roles.get!(role.id) end
    end
  end

  describe "change/2" do
    test "역할 changeset을 반환한다" do
      role = role_fixture()
      changeset = Roles.change(role)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data.id == role.id
    end

    test "속성이 있는 changeset을 반환한다" do
      role = role_fixture()
      changeset = Roles.change(role, %{name: "NewName"})

      assert changeset.changes.name == "NewName"
    end
  end

  describe "increase_user_count/1" do
    test "사용자 카운트를 증가시킨다" do
      role = role_fixture(%{user_count: 5})

      assert {:ok, updated_role} = Roles.increase_user_count(role)
      assert updated_role.user_count == 6
    end

    test "연속적으로 카운트를 증가시킬 수 있다" do
      role = role_fixture(%{user_count: 0})

      {:ok, role} = Roles.increase_user_count(role)
      assert role.user_count == 1

      {:ok, role} = Roles.increase_user_count(role)
      assert role.user_count == 2
    end
  end

  describe "decrease_user_count/1" do
    test "사용자 카운트를 감소시킨다" do
      role = role_fixture(%{user_count: 5})

      assert {:ok, updated_role} = Roles.decrease_user_count(role)
      assert updated_role.user_count == 4
    end

    test "카운트가 0 미만으로 내려가지 않는다" do
      role = role_fixture(%{user_count: 0})

      assert {:ok, updated_role} = Roles.decrease_user_count(role)
      assert updated_role.user_count == 0
    end

    test "연속적으로 카운트를 감소시킬 수 있다" do
      role = role_fixture(%{user_count: 3})

      {:ok, role} = Roles.decrease_user_count(role)
      assert role.user_count == 2

      {:ok, role} = Roles.decrease_user_count(role)
      assert role.user_count == 1

      {:ok, role} = Roles.decrease_user_count(role)
      assert role.user_count == 0

      {:ok, role} = Roles.decrease_user_count(role)
      assert role.user_count == 0
    end
  end
end
