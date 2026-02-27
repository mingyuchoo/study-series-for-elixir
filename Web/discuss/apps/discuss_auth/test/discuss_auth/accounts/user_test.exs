defmodule DiscussAuth.Accounts.UserTest do
  use Discuss.DataCase

  alias DiscussAuth.Accounts.User

  describe "registration_changeset/3" do
    test "유효한 데이터로 유효한 changeset을 반환한다" do
      changeset = User.registration_changeset(%User{}, %{email: "test@example.com", password: "valid_password!"})
      assert changeset.valid?
    end

    test "이메일이 없으면 에러를 반환한다" do
      changeset = User.registration_changeset(%User{}, %{password: "valid_password!"})
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "비밀번호가 없으면 에러를 반환한다" do
      changeset = User.registration_changeset(%User{}, %{email: "test@example.com"})
      assert %{password: ["can't be blank"]} = errors_on(changeset)
    end

    test "이메일 형식이 올바르지 않으면 에러를 반환한다" do
      changeset = User.registration_changeset(%User{}, %{email: "invalid", password: "valid_password!"})
      assert %{email: [_]} = errors_on(changeset)
    end

    test "이메일이 160자를 초과하면 에러를 반환한다" do
      email = String.duplicate("a", 150) <> "@example.com"
      changeset = User.registration_changeset(%User{}, %{email: email, password: "valid_password!"})
      assert %{email: [_]} = errors_on(changeset)
    end

    test "비밀번호가 8자 미만이면 에러를 반환한다" do
      changeset = User.registration_changeset(%User{}, %{email: "test@example.com", password: "short"})
      assert %{password: [_]} = errors_on(changeset)
    end

    test "비밀번호가 72자를 초과하면 에러를 반환한다" do
      password = String.duplicate("a", 73)
      changeset = User.registration_changeset(%User{}, %{email: "test@example.com", password: password})
      assert %{password: [_]} = errors_on(changeset)
    end

    test "hash_password: false 옵션으로 비밀번호를 해싱하지 않는다" do
      changeset = User.registration_changeset(%User{}, %{email: "test@example.com", password: "valid_password!"}, hash_password: false)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :password) == "valid_password!"
      refute Ecto.Changeset.get_change(changeset, :hashed_password)
    end

    test "validate_email: false 옵션으로 유니크 검증을 건너뛴다" do
      changeset = User.registration_changeset(%User{}, %{email: "test@example.com", password: "valid_password!"}, validate_email: false)
      assert changeset.valid?
    end
  end

  describe "email_changeset/3" do
    test "이메일을 변경하면 유효한 changeset을 반환한다" do
      user = %User{email: "old@example.com"}
      changeset = User.email_changeset(user, %{email: "new@example.com"})
      assert changeset.valid?
    end

    test "이메일 변경사항이 없으면 에러를 반환한다" do
      user = %User{email: "same@example.com"}
      changeset = User.email_changeset(user, %{email: "same@example.com"})
      assert %{email: ["변경사항이 없습니다"]} = errors_on(changeset)
    end
  end

  describe "password_changeset/3" do
    test "유효한 비밀번호로 유효한 changeset을 반환한다" do
      user = %User{email: "test@example.com"}
      changeset = User.password_changeset(user, %{password: "new_password!", password_confirmation: "new_password!"})
      assert changeset.valid?
    end

    test "비밀번호 확인이 일치하지 않으면 에러를 반환한다" do
      user = %User{email: "test@example.com"}
      changeset = User.password_changeset(user, %{password: "new_password!", password_confirmation: "different"})
      assert %{password_confirmation: [_]} = errors_on(changeset)
    end

    test "hash_password: false 옵션으로 비밀번호를 해싱하지 않는다" do
      user = %User{email: "test@example.com"}
      changeset = User.password_changeset(user, %{password: "new_password!"}, hash_password: false)
      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :hashed_password)
    end
  end

  describe "confirm_changeset/1" do
    test "confirmed_at을 설정한다" do
      user = %User{}
      changeset = User.confirm_changeset(user)
      assert Ecto.Changeset.get_change(changeset, :confirmed_at)
    end
  end

  describe "valid_password?/2" do
    test "올바른 비밀번호로 true를 반환한다" do
      hashed = Pbkdf2.hash_pwd_salt("correct_password")
      user = %User{hashed_password: hashed}
      assert User.valid_password?(user, "correct_password")
    end

    test "틀린 비밀번호로 false를 반환한다" do
      hashed = Pbkdf2.hash_pwd_salt("correct_password")
      user = %User{hashed_password: hashed}
      refute User.valid_password?(user, "wrong_password")
    end

    test "해시가 없으면 false를 반환한다" do
      refute User.valid_password?(%User{hashed_password: nil}, "password")
    end

    test "nil 사용자도 false를 반환한다" do
      refute User.valid_password?(nil, "password")
    end
  end

  describe "validate_current_password/2" do
    test "올바른 비밀번호로 changeset을 변경하지 않는다" do
      hashed = Pbkdf2.hash_pwd_salt("current_password")
      user = %User{hashed_password: hashed}
      changeset = Ecto.Changeset.change(user)
      result = User.validate_current_password(changeset, "current_password")
      assert result.valid?
    end

    test "틀린 비밀번호로 에러를 추가한다" do
      hashed = Pbkdf2.hash_pwd_salt("current_password")
      user = %User{hashed_password: hashed}
      changeset = Ecto.Changeset.change(user)
      result = User.validate_current_password(changeset, "wrong")
      assert %{current_password: ["올바르지 않습니다"]} = errors_on(result)
    end
  end
end
