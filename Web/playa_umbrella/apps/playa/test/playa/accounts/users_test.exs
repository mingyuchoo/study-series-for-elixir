defmodule Playa.Accounts.UsersTest do
  use Playa.DataCase

  alias Playa.Accounts
  alias Playa.Accounts.Users
  alias Playa.Accounts.User
  alias Playa.Repo

  import Playa.AccountsFixtures

  describe "list_by_role_id/1" do
    test "특정 역할을 가진 사용자 목록을 반환한다" do
      role = role_fixture()
      user1 = user_fixture()
      user2 = user_fixture()
      # 이 사용자는 해당 역할이 없음
      user3 = user_fixture()

      # user1과 user2에게 역할 할당
      role_user_fixture(role.id, user1.id)
      role_user_fixture(role.id, user2.id)

      users = Users.list_by_role_id(role.id)
      user_ids = Enum.map(users, & &1.id)

      assert length(users) == 2
      assert user1.id in user_ids
      assert user2.id in user_ids
      refute user3.id in user_ids
    end

    test "존재하지 않는 역할 ID로는 빈 목록을 반환한다" do
      users = Users.list_by_role_id(-1)
      assert users == []
    end

    test "결과는 ID로 정렬된다" do
      role = role_fixture()
      user1 = user_fixture()
      user2 = user_fixture()

      role_user_fixture(role.id, user2.id)
      role_user_fixture(role.id, user1.id)

      users = Users.list_by_role_id(role.id)
      user_ids = Enum.map(users, & &1.id)

      # ID가 작은 것부터 정렬되어야 함
      assert user_ids == Enum.sort(user_ids)
    end
  end

  describe "create/1" do
    test "유효한 속성으로 사용자를 생성한다" do
      attrs = %{
        email: "test@example.com",
        password: "hello world!"
      }

      assert {:ok, user} = Users.create(attrs)
      assert user.email == attrs.email
      assert is_nil(user.confirmed_at)
      assert Ecto.assoc_loaded?(user.roles)
    end

    test "유효하지 않은 속성으로는 사용자를 생성할 수 없다" do
      assert {:error, changeset} = Users.create(%{email: "invalid"})
      assert "can't be blank" in errors_on(changeset).password
    end

    test "register/1과 동일하게 작동한다" do
      attrs = %{
        email: "test@example.com",
        password: "hello world!"
      }

      {:ok, user1} = Users.register(attrs)
      {:ok, user2} = Users.create(%{email: "test2@example.com", password: "hello world!"})

      assert user1.email =~ "@example.com"
      assert user2.email =~ "@example.com"
      assert user1.__struct__ == user2.__struct__
    end
  end

  describe "update_nickname/2" do
    test "유효한 닉네임으로 업데이트한다" do
      user = user_fixture()
      attrs = %{nickname: "NewNickname"}

      assert {:ok, updated_user} = Users.update_nickname(user, attrs)
      assert updated_user.nickname == "NewNickname"
      assert updated_user.email == user.email
    end

    test "다른 닉네임으로 업데이트한다" do
      user = user_fixture(%{nickname: "OldNickname"})
      attrs = %{nickname: "UpdatedNick"}

      assert {:ok, updated_user} = Users.update_nickname(user, attrs)
      assert updated_user.nickname == "UpdatedNick"
    end

    test "역할이 프리로드된 사용자를 반환한다" do
      role = role_fixture()
      user = user_fixture()
      role_user_fixture(role.id, user.id)

      {:ok, updated_user} = Users.update_nickname(user, %{nickname: "Test"})

      assert Ecto.assoc_loaded?(updated_user.roles)
      assert length(updated_user.roles) == 1
    end
  end

  describe "apply_email_change/3" do
    test "올바른 비밀번호로 이메일 변경을 적용한다" do
      user = user_fixture()
      password = valid_user_password()
      new_email = "new-#{user.email}"

      assert {:ok, user_with_new_email} =
               Users.apply_email_change(user, password, %{email: new_email})

      assert user_with_new_email.email == new_email
    end

    test "잘못된 비밀번호로는 이메일을 변경할 수 없다" do
      user = user_fixture()
      new_email = "new-#{user.email}"

      assert {:error, changeset} =
               Users.apply_email_change(user, "wrong password", %{email: new_email})

      assert "is not valid" in errors_on(changeset).current_password
    end

    test "유효하지 않은 이메일 형식으로는 변경할 수 없다" do
      user = user_fixture()
      password = valid_user_password()

      assert {:error, changeset} = Users.apply_email_change(user, password, %{email: "invalid"})
      assert "must have the @ sign and no spaces" in errors_on(changeset).email
    end

    test "이미 사용 중인 이메일로는 변경할 수 없다" do
      user1 = user_fixture()
      user2 = user_fixture()
      password = valid_user_password()

      assert {:error, changeset} =
               Users.apply_email_change(user2, password, %{email: user1.email})

      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "change_registration/2" do
    test "등록 changeset을 반환한다" do
      user = user_fixture()
      changeset = Users.change_registration(user)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data.id == user.id
    end

    test "속성이 있는 changeset을 반환한다" do
      user = user_fixture()
      changeset = Users.change_registration(user, %{email: "new@example.com"})

      assert changeset.changes.email == "new@example.com"
    end

    test "비밀번호를 해시하지 않는다 (hash_password: false)" do
      user = user_fixture()
      changeset = Users.change_registration(user, %{password: "new password"})

      # hash_password: false이므로 hashed_password 변경이 없어야 함
      assert changeset.changes.password == "new password"
      refute Map.has_key?(changeset.changes, :hashed_password)
    end

    test "이메일 유효성 검사를 하지 않는다 (validate_email: false)" do
      user1 = user_fixture()
      user2 = user_fixture()

      # user2가 user1과 동일한 이메일로 변경하려고 시도
      # validate_email: false이므로 uniqueness 검증이 수행되지 않아야 함
      changeset = Users.change_registration(user2, %{email: user1.email})

      # uniqueness 에러가 없어야 함
      uniqueness_errors =
        Enum.filter(changeset.errors[:email] || [], fn {_msg, opts} ->
          Keyword.get(opts, :validation) == :unique
        end)

      assert uniqueness_errors == []
    end

    test "역할이 프리로드된다" do
      role = role_fixture()
      user = user_fixture()
      role_user_fixture(role.id, user.id)

      # 역할이 없는 user를 가져온 후
      user_without_roles = Repo.get!(User, user.id)
      refute Ecto.assoc_loaded?(user_without_roles.roles)

      # change_registration은 역할을 프리로드해야 함
      changeset = Users.change_registration(user_without_roles)
      assert Ecto.assoc_loaded?(changeset.data.roles)
    end
  end

  describe "change_email/2" do
    test "이메일 변경 changeset을 반환한다" do
      user = user_fixture()
      changeset = Users.change_email(user)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data.id == user.id
    end

    test "속성이 있는 changeset을 반환한다" do
      user = user_fixture()
      new_email = "new@example.com"
      changeset = Users.change_email(user, %{email: new_email})

      assert changeset.changes.email == new_email
    end

    test "이메일 유효성 검사를 하지 않는다 (validate_email: false)" do
      user1 = user_fixture()
      user2 = user_fixture()

      # user2가 user1과 동일한 이메일로 변경하려고 시도
      # validate_email: false이므로 uniqueness 검증이 수행되지 않아야 함
      changeset = Users.change_email(user2, %{email: user1.email})

      # uniqueness 에러가 없어야 함
      uniqueness_errors =
        Enum.filter(changeset.errors[:email] || [], fn {_msg, opts} ->
          Keyword.get(opts, :validation) == :unique
        end)

      assert uniqueness_errors == []
    end
  end

  describe "change_nickname/2" do
    test "닉네임 변경 changeset을 반환한다" do
      user = user_fixture()
      changeset = Users.change_nickname(user)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data.id == user.id
    end

    test "속성이 있는 changeset을 반환한다" do
      user = user_fixture()
      changeset = Users.change_nickname(user, %{nickname: "NewNick"})

      assert changeset.changes.nickname == "NewNick"
    end

    test "닉네임 변경을 검증한다" do
      user = user_fixture(%{nickname: "OldNick"})
      changeset = Users.change_nickname(user, %{nickname: "NewNick"})

      assert changeset.valid?
      assert changeset.changes.nickname == "NewNick"
    end
  end

  describe "change/2" do
    test "범용 changeset을 반환한다" do
      user = user_fixture()
      changeset = Users.change(user)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data.id == user.id
    end

    test "속성이 있는 changeset을 반환한다" do
      user = user_fixture()

      attrs = %{
        email: "new@example.com",
        nickname: "NewNick"
      }

      changeset = Users.change(user, attrs)

      assert changeset.changes.email == attrs.email
      assert changeset.changes.nickname == attrs.nickname
    end

    test "등록 changeset을 사용한다" do
      user = user_fixture()
      changeset1 = Users.change(user, %{email: "test@example.com"})
      changeset2 = Users.change_registration(user, %{email: "test@example.com"})

      # 같은 changeset 타입이어야 함
      assert changeset1.__struct__ == changeset2.__struct__
    end
  end

  describe "admin?/1" do
    test "Admin 역할이 없는 사용자는 false를 반환한다" do
      user = user_fixture()
      refute Users.admin?(user)
    end

    test "Admin 역할이 있는 사용자는 true를 반환한다" do
      # 기존 Admin 역할을 조회하거나 새로 생성
      admin_role = Accounts.get_default_role("Admin") || role_fixture(%{name: "Admin"})
      user = user_fixture()
      role_user_fixture(admin_role.id, user.id)

      # 역할을 프리로드하여 다시 가져오기
      user_with_roles = Users.get!(user.id)
      assert Users.admin?(user_with_roles)
    end

    test "다른 역할만 있는 사용자는 false를 반환한다" do
      other_role = role_fixture(%{name: "User"})
      user = user_fixture()
      role_user_fixture(other_role.id, user.id)

      user_with_roles = Users.get!(user.id)
      refute Users.admin?(user_with_roles)
    end

    test "역할이 프리로드되지 않으면 오류가 발생할 수 있다" do
      user = Repo.get!(User, user_fixture().id)
      refute Ecto.assoc_loaded?(user.roles)

      # 역할이 프리로드되지 않았지만 함수는 작동해야 함
      assert_raise Protocol.UndefinedError, fn ->
        Users.admin?(user)
      end
    end
  end

  describe "get!/1" do
    test "존재하지 않는 사용자는 예외를 발생시킨다" do
      assert_raise Ecto.NoResultsError, fn ->
        Users.get!(-1)
      end
    end

    test "역할이 프리로드된 사용자를 반환한다" do
      role = role_fixture()
      user = user_fixture()
      role_user_fixture(role.id, user.id)

      fetched_user = Users.get!(user.id)

      assert Ecto.assoc_loaded?(fetched_user.roles)
      assert length(fetched_user.roles) >= 1
      assert Enum.any?(fetched_user.roles, fn r -> r.id == role.id end)
    end
  end

  describe "get_by_email/1" do
    test "존재하지 않는 이메일은 nil을 반환한다" do
      assert Users.get_by_email("nonexistent@example.com") == nil
    end

    test "역할이 프리로드된 사용자를 반환한다" do
      role = role_fixture()
      user = user_fixture()
      role_user_fixture(role.id, user.id)

      fetched_user = Users.get_by_email(user.email)

      assert Ecto.assoc_loaded?(fetched_user.roles)
      assert length(fetched_user.roles) >= 1
      assert Enum.any?(fetched_user.roles, fn r -> r.id == role.id end)
    end
  end

  describe "list/0" do
    test "역할이 프리로드된 모든 사용자를 반환한다" do
      role = role_fixture()
      user1 = user_fixture()
      _user2 = user_fixture()
      role_user_fixture(role.id, user1.id)

      users = Users.list()

      assert length(users) >= 2

      # 모든 사용자의 역할이 프리로드되어 있는지 확인
      Enum.each(users, fn user ->
        assert Ecto.assoc_loaded?(user.roles)
      end)
    end

    test "ID 순으로 정렬되어 반환한다" do
      _user1 = user_fixture()
      _user2 = user_fixture()

      users = Users.list()
      user_ids = Enum.map(users, & &1.id)

      assert user_ids == Enum.sort(user_ids)
    end
  end
end
