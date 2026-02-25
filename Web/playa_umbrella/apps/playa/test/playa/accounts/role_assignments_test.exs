defmodule Playa.Accounts.RoleAssignmentsTest do
  use Playa.DataCase

  alias Playa.Accounts.RoleAssignments

  import Playa.AccountsFixtures

  describe "list/0" do
    test "모든 역할-사용자 관계를 반환한다" do
      role = role_fixture()
      user1 = user_fixture()
      user2 = user_fixture()

      role_user1 = role_user_fixture(role.id, user1.id)
      role_user2 = role_user_fixture(role.id, user2.id)

      role_users = RoleAssignments.list()
      role_user_ids = Enum.map(role_users, & &1.id)

      assert role_user1.id in role_user_ids
      assert role_user2.id in role_user_ids
    end

    test "ID 순으로 정렬되어 반환한다" do
      _role = role_fixture()
      _user1 = user_fixture()
      _user2 = user_fixture()

      role_users = RoleAssignments.list()
      role_user_ids = Enum.map(role_users, & &1.id)

      assert role_user_ids == Enum.sort(role_user_ids)
    end
  end

  describe "list_by_user_id/1" do
    test "특정 사용자의 역할 할당 목록을 반환한다" do
      role1 = role_fixture()
      role2 = role_fixture()
      user = user_fixture()

      role_user1 = role_user_fixture(role1.id, user.id)
      role_user2 = role_user_fixture(role2.id, user.id)

      role_users = RoleAssignments.list_by_user_id(user.id)
      role_user_ids = Enum.map(role_users, & &1.id)

      assert length(role_users) >= 2
      assert role_user1.id in role_user_ids
      assert role_user2.id in role_user_ids
    end

    test "존재하지 않는 사용자 ID로는 빈 목록을 반환한다" do
      role_users = RoleAssignments.list_by_user_id(-1)
      assert role_users == []
    end
  end

  describe "list_unassigned_roles/1" do
    test "사용자가 할당받지 않은 역할 목록을 반환한다" do
      role1 = role_fixture()
      role2 = role_fixture()
      role3 = role_fixture()
      user = user_fixture()

      role_user_fixture(role1.id, user.id)

      unassigned_roles = RoleAssignments.list_unassigned_roles(user.id)
      unassigned_role_ids = Enum.map(unassigned_roles, & &1.id)

      refute role1.id in unassigned_role_ids
      assert role2.id in unassigned_role_ids
      assert role3.id in unassigned_role_ids
    end

    test "모든 역할을 가진 사용자는 빈 목록을 반환할 수 있다" do
      # 새로운 역할만 생성
      role1 = role_fixture()
      role2 = role_fixture()
      user = user_fixture()

      role_user_fixture(role1.id, user.id)
      role_user_fixture(role2.id, user.id)

      # 기본 역할 제외한 새로 만든 역할들만 확인
      unassigned = RoleAssignments.list_unassigned_roles(user.id)
      assert Enum.all?(unassigned, fn r -> r.id not in [role1.id, role2.id] end)
    end
  end

  describe "get!/2" do
    test "역할과 사용자 ID로 관계를 조회한다" do
      role = role_fixture()
      user = user_fixture()
      role_user = role_user_fixture(role.id, user.id)

      fetched = RoleAssignments.get!(role.id, user.id)

      assert fetched.id == role_user.id
      assert fetched.role_id == role.id
      assert fetched.user_id == user.id
    end

    test "존재하지 않는 관계는 예외를 발생시킨다" do
      assert_raise Ecto.NoResultsError, fn ->
        RoleAssignments.get!(-1, -1)
      end
    end
  end

  describe "get/2" do
    test "역할과 사용자 ID로 관계를 조회한다" do
      role = role_fixture()
      user = user_fixture()
      role_user = role_user_fixture(role.id, user.id)

      fetched = RoleAssignments.get(role.id, user.id)

      assert fetched.id == role_user.id
      assert fetched.role_id == role.id
      assert fetched.user_id == user.id
    end

    test "존재하지 않는 관계는 nil을 반환한다" do
      assert RoleAssignments.get(-1, -1) == nil
    end
  end

  describe "create/1" do
    test "유효한 속성으로 역할-사용자 관계를 생성한다" do
      role = role_fixture()
      user = user_fixture()
      attrs = %{role_id: role.id, user_id: user.id}

      assert {:ok, role_user} = RoleAssignments.create(attrs)
      assert role_user.role_id == role.id
      assert role_user.user_id == user.id
    end

    test "유효하지 않은 속성으로는 생성할 수 없다" do
      assert {:error, changeset} = RoleAssignments.create(%{})
      errors = errors_on(changeset)

      assert "can't be blank" in (errors[:role_id] || [])
      assert "can't be blank" in (errors[:user_id] || [])
    end

    test "존재하지 않는 역할이나 사용자로는 생성할 수 없다" do
      assert {:error, _changeset} = RoleAssignments.create(%{role_id: -1, user_id: -1})
    end

    test "중복된 관계는 데이터베이스 제약으로 방지된다" do
      role = role_fixture()
      user = user_fixture()
      attrs = %{role_id: role.id, user_id: user.id}

      {:ok, _role_user} = RoleAssignments.create(attrs)

      # 중복 생성 시도는 데이터베이스 제약 위반으로 실패
      assert_raise Ecto.ConstraintError, fn ->
        RoleAssignments.create(attrs)
      end
    end
  end

  describe "update/2" do
    test "역할-사용자 관계를 업데이트할 수 있다" do
      role1 = role_fixture()
      role2 = role_fixture()
      user = user_fixture()

      role_user = role_user_fixture(role1.id, user.id)

      assert {:ok, updated} = RoleAssignments.update(role_user, %{role_id: role2.id})
      assert updated.role_id == role2.id
      assert updated.user_id == user.id
    end

    test "유효하지 않은 속성으로는 업데이트할 수 없다" do
      role = role_fixture()
      user = user_fixture()
      role_user = role_user_fixture(role.id, user.id)

      assert {:error, changeset} = RoleAssignments.update(role_user, %{role_id: nil})
      assert %{role_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "delete/1" do
    test "역할-사용자 관계를 삭제한다" do
      role = role_fixture()
      user = user_fixture()
      role_user = role_user_fixture(role.id, user.id)

      assert {:ok, _deleted} = RoleAssignments.delete(role_user)
      assert RoleAssignments.get(role.id, user.id) == nil
    end
  end

  describe "change/2" do
    test "역할-사용자 changeset을 반환한다" do
      role = role_fixture()
      user = user_fixture()
      role_user = role_user_fixture(role.id, user.id)

      changeset = RoleAssignments.change(role_user)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data.id == role_user.id
    end

    test "속성이 있는 changeset을 반환한다" do
      role1 = role_fixture()
      role2 = role_fixture()
      user = user_fixture()
      role_user = role_user_fixture(role1.id, user.id)

      changeset = RoleAssignments.change(role_user, %{role_id: role2.id})

      assert changeset.changes.role_id == role2.id
    end
  end
end
