defmodule Discuss.Admin.UserTest do
  use Discuss.DataCase

  alias Discuss.Admin.User

  describe "changeset/2" do
    test "유효한 속성으로 유효한 changeset을 반환한다" do
      changeset =
        User.changeset(%User{}, %{
          name: "홍길동",
          email: "hong@example.com",
          role: "admin",
          address: "서울시 강남구"
        })

      assert changeset.valid?
    end

    test "이름이 없으면 에러를 반환한다" do
      changeset =
        User.changeset(%User{}, %{
          email: "hong@example.com",
          role: "admin",
          address: "서울시"
        })

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "이메일이 없으면 에러를 반환한다" do
      changeset =
        User.changeset(%User{}, %{
          name: "홍길동",
          role: "admin",
          address: "서울시"
        })

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "역할이 없으면 에러를 반환한다" do
      changeset =
        User.changeset(%User{}, %{
          name: "홍길동",
          email: "hong@example.com",
          address: "서울시"
        })

      assert %{role: ["can't be blank"]} = errors_on(changeset)
    end

    test "주소가 없으면 에러를 반환한다" do
      changeset =
        User.changeset(%User{}, %{
          name: "홍길동",
          email: "hong@example.com",
          role: "admin"
        })

      assert %{address: ["can't be blank"]} = errors_on(changeset)
    end

    test "auth_user_id를 설정할 수 있다" do
      changeset =
        User.changeset(%User{}, %{
          name: "홍길동",
          email: "hong@example.com",
          role: "admin",
          address: "서울시",
          auth_user_id: 42
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :auth_user_id) == 42
    end
  end
end
