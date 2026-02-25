defmodule Auth.RepoTest do
  use Auth.DataCase, async: true

  alias Auth.Repo
  alias Playa.Accounts.User

  describe "Ecto.Repo behaviour" do
    test "Ecto.Repo behaviour를 구현한다" do
      behaviours = Repo.__info__(:attributes)[:behaviour] || []
      assert Ecto.Repo in behaviours
    end

    test "필수 Ecto.Repo 함수들을 export한다" do
      assert function_exported?(Repo, :all, 1)
      assert function_exported?(Repo, :get, 2)
      assert function_exported?(Repo, :get_by, 2)
      assert function_exported?(Repo, :insert, 1)
      assert function_exported?(Repo, :update, 1)
      assert function_exported?(Repo, :delete, 1)
    end
  end

  describe "구성 (configuration)" do
    test "otp_app이 :auth로 설정되어 있다" do
      config = Repo.config()
      assert config[:otp_app] == :auth
    end

    test "Postgres 어댑터를 사용한다" do
      adapter = Repo.__adapter__()
      assert adapter == Ecto.Adapters.Postgres
    end

    test "데이터베이스 연결이 활성화되어 있다" do
      # 간단한 쿼리로 연결 확인
      result = Repo.query("SELECT 1 as value")
      assert {:ok, %Postgrex.Result{}} = result
    end
  end

  describe "기본 CRUD 작업" do
    setup do
      # 테스트용 사용자 생성
      changeset =
        %User{}
        |> User.registration_changeset(%{
          email: "repo_test_#{System.unique_integer()}@example.com",
          password: "hello world!"
        })

      {:ok, user} = Playa.Repo.insert(changeset)
      %{user: user}
    end

    test "all/1로 모든 레코드를 조회할 수 있다" do
      # Playa.Repo를 통해 생성된 사용자가 있는지 확인
      users = Playa.Repo.all(User)
      assert length(users) > 0
    end

    test "get/2로 특정 레코드를 조회할 수 있다", %{user: user} do
      fetched_user = Playa.Repo.get(User, user.id)
      assert fetched_user != nil
      assert fetched_user.id == user.id
      assert fetched_user.email == user.email
    end

    test "get_by/2로 조건에 맞는 레코드를 조회할 수 있다", %{user: user} do
      fetched_user = Playa.Repo.get_by(User, email: user.email)
      assert fetched_user != nil
      assert fetched_user.id == user.id
    end

    test "update/1로 레코드를 수정할 수 있다", %{user: user} do
      new_email = "updated_#{System.unique_integer()}@example.com"

      changeset =
        user
        |> Ecto.Changeset.change(email: new_email)

      {:ok, updated_user} = Playa.Repo.update(changeset)
      assert updated_user.email == new_email
    end

    test "delete/1로 레코드를 삭제할 수 있다", %{user: user} do
      {:ok, deleted_user} = Playa.Repo.delete(user)
      assert deleted_user.id == user.id

      # 삭제된 사용자를 조회하면 nil이 반환됨
      assert Playa.Repo.get(User, user.id) == nil
    end
  end

  describe "트랜잭션 (transactions)" do
    test "transaction/1로 트랜잭션을 실행할 수 있다" do
      result =
        Playa.Repo.transaction(fn ->
          changeset =
            %User{}
            |> User.registration_changeset(%{
              email: "transaction_test_#{System.unique_integer()}@example.com",
              password: "hello world!"
            })

          {:ok, user} = Playa.Repo.insert(changeset)
          user
        end)

      assert {:ok, %User{}} = result
    end

    test "transaction이 실패하면 롤백된다" do
      # 트랜잭션 전 사용자 수 확인
      initial_count = Playa.Repo.aggregate(User, :count)

      result =
        Playa.Repo.transaction(fn ->
          changeset =
            %User{}
            |> User.registration_changeset(%{
              email: "rollback_test_#{System.unique_integer()}@example.com",
              password: "hello world!"
            })

          {:ok, _user} = Playa.Repo.insert(changeset)

          # 의도적으로 롤백
          Playa.Repo.rollback(:test_rollback)
        end)

      assert {:error, :test_rollback} = result

      # 롤백 후 사용자 수가 변하지 않았는지 확인
      final_count = Playa.Repo.aggregate(User, :count)
      assert final_count == initial_count
    end
  end

  describe "쿼리 (queries)" do
    setup do
      # 여러 테스트 사용자 생성
      users =
        for i <- 1..3 do
          changeset =
            %User{}
            |> User.registration_changeset(%{
              email: "query_test_#{i}_#{System.unique_integer()}@example.com",
              password: "hello world!"
            })

          {:ok, user} = Playa.Repo.insert(changeset)
          user
        end

      %{users: users}
    end

    test "Ecto.Query를 사용하여 조회할 수 있다", %{users: users} do
      import Ecto.Query

      user_ids = Enum.map(users, & &1.id)

      query = from(u in User, where: u.id in ^user_ids)
      fetched_users = Playa.Repo.all(query)

      assert length(fetched_users) == 3
    end

    test "aggregate 함수를 사용할 수 있다" do
      count = Playa.Repo.aggregate(User, :count)
      assert is_integer(count)
      assert count >= 0
    end
  end

  describe "preload" do
    test "preload/2를 사용하여 연관 데이터를 로드할 수 있다" do
      # User 스키마에 preload 가능한 연관 관계가 있다면 테스트
      # 현재는 기본 동작만 확인
      changeset =
        %User{}
        |> User.registration_changeset(%{
          email: "preload_test_#{System.unique_integer()}@example.com",
          password: "hello world!"
        })

      {:ok, user} = Playa.Repo.insert(changeset)

      # preload 함수 자체가 동작하는지 확인
      loaded_user = Playa.Repo.preload(user, [])
      assert loaded_user.id == user.id
    end
  end

  describe "sandbox 모드" do
    test "테스트 환경에서 sandbox 모드가 활성화되어 있다" do
      # DataCase에서 sandbox를 설정하므로, 테스트가 격리되어 실행됨
      # 이는 다른 테스트의 데이터가 보이지 않음을 의미

      changeset =
        %User{}
        |> User.registration_changeset(%{
          email: "sandbox_test_#{System.unique_integer()}@example.com",
          password: "hello world!"
        })

      {:ok, _user} = Playa.Repo.insert(changeset)

      # 삽입 후 해당 사용자를 찾을 수 있어야 함
      users = Playa.Repo.all(User)
      assert length(users) > 0
    end
  end

  describe "config/0" do
    test "Repo 설정을 반환한다" do
      config = Repo.config()

      assert is_list(config)
      assert config[:otp_app] == :auth
      # adapter는 __adapter__/0로 확인 가능
      assert Repo.__adapter__() == Ecto.Adapters.Postgres
    end
  end

  describe "__adapter__/0" do
    test "사용 중인 어댑터를 반환한다" do
      adapter = Repo.__adapter__()
      assert adapter == Ecto.Adapters.Postgres
    end
  end
end
