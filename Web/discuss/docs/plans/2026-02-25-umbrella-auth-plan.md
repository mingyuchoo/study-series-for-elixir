# 엄브렐라 구조 전환 + 인증 시스템 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 기존 단일(flat) Phoenix 프로젝트를 3개 앱(discuss, discuss_auth, discuss_web) 엄브렐라 구조로 전환하고, phx.gen.auth 패턴 기반 회원가입/로그인 기능을 추가한다.

**Architecture:** 엄브렐라 루트 아래 3개 OTP 앱으로 분리한다. `discuss`는 Repo와 도메인 로직(Topics, Admin), `discuss_auth`는 인증 컨텍스트(Accounts, User, UserToken), `discuss_web`은 Phoenix 웹 계층을 담당한다. 모든 앱은 하나의 Repo(Discuss.Repo)를 공유한다.

**Tech Stack:** Elixir 1.19, Phoenix 1.7.21, Ecto, PostgreSQL, bcrypt_elixir, Tailwind, Bandit

---

## Task 1: 엄브렐라 프로젝트 뼈대 생성

현재 프로젝트를 백업하고, 같은 위치에 엄브렐라 구조를 생성한다.

**Files:**
- Create: `mix.exs` (엄브렐라 루트, 기존 것을 대체)
- Create: `apps/` 디렉토리
- Modify: `.gitignore`
- Move: `config/` (엄브렐라 루트에 유지)

**Step 1: 기존 프로젝트 백업**

```bash
cd /c/Users/mingy/github/mingyuchoo/elixir-study-series/Web
cp -r discuss discuss_backup
```

**Step 2: 기존 빌드 아티팩트 정리**

```bash
cd /c/Users/mingy/github/mingyuchoo/elixir-study-series/Web/discuss
rm -rf _build deps
```

**Step 3: 엄브렐라 루트 mix.exs 작성**

`mix.exs`를 엄브렐라 루트용으로 교체:

```elixir
defmodule Discuss.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp deps do
    []
  end

  defp aliases do
    [
      setup: ["cmd mix setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run apps/discuss/priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
```

**Step 4: apps 디렉토리 생성**

```bash
mkdir -p apps
```

**Step 5: .formatter.exs 업데이트**

루트 `.formatter.exs`:

```elixir
[
  import_deps: [],
  subdirectories: ["apps/*"]
]
```

**Step 6: 컴파일 확인 (아직 앱이 없으므로 경고만 나옴)**

Run: `mix deps.get`
Expected: 성공 (앱이 없다는 경고)

**Step 7: 커밋**

```bash
git add mix.exs .formatter.exs apps/
git commit -m "refactor: 엄브렐라 프로젝트 루트 구조 설정"
```

---

## Task 2: apps/discuss 앱 생성 (도메인 + Repo)

Repo, 스키마, 컨텍스트, 마이그레이션을 담는 핵심 도메인 앱을 생성한다.

**Files:**
- Create: `apps/discuss/mix.exs`
- Create: `apps/discuss/lib/discuss.ex`
- Create: `apps/discuss/lib/discuss/application.ex`
- Create: `apps/discuss/lib/discuss/repo.ex`
- Create: `apps/discuss/lib/discuss/mailer.ex`
- Create: `apps/discuss/lib/discuss/topics.ex`
- Create: `apps/discuss/lib/discuss/topics/topic.ex`
- Create: `apps/discuss/lib/discuss/admin.ex`
- Create: `apps/discuss/lib/discuss/admin/user.ex`
- Move: `priv/repo/migrations/*` → `apps/discuss/priv/repo/migrations/`
- Create: `apps/discuss/priv/repo/seeds.exs`
- Create: `apps/discuss/test/test_helper.exs`
- Create: `apps/discuss/test/support/data_case.ex`
- Create: `apps/discuss/.formatter.exs`

**Step 1: 디렉토리 구조 생성**

```bash
mkdir -p apps/discuss/lib/discuss/topics
mkdir -p apps/discuss/lib/discuss/admin
mkdir -p apps/discuss/priv/repo/migrations
mkdir -p apps/discuss/test/support/fixtures
```

**Step 2: apps/discuss/mix.exs 작성**

```elixir
defmodule Discuss.MixProject do
  use Mix.Project

  def project do
    [
      app: :discuss,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Discuss.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},
      {:dns_cluster, "~> 0.2.0"},
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
```

**Step 3: 기존 코드 복사 (discuss 도메인 파일들)**

기존 파일들을 apps/discuss/로 복사:

- `lib/discuss.ex` → `apps/discuss/lib/discuss.ex` (내용 유지)
- `lib/discuss/repo.ex` → `apps/discuss/lib/discuss/repo.ex` (내용 유지)
- `lib/discuss/mailer.ex` → `apps/discuss/lib/discuss/mailer.ex` (내용 유지)
- `lib/discuss/topics.ex` → `apps/discuss/lib/discuss/topics.ex` (내용 유지)
- `lib/discuss/topics/topic.ex` → `apps/discuss/lib/discuss/topics/topic.ex` (내용 유지)
- `lib/discuss/admin.ex` → `apps/discuss/lib/discuss/admin.ex` (내용 유지)
- `lib/discuss/admin/user.ex` → `apps/discuss/lib/discuss/admin/user.ex` (내용 유지)

**Step 4: Application 모듈 작성 (Repo만 시작)**

`apps/discuss/lib/discuss/application.ex`:

```elixir
defmodule Discuss.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Discuss.Repo,
      {DNSCluster, query: Application.get_env(:discuss, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Discuss.PubSub},
      {Finch, name: Discuss.Finch}
    ]

    opts = [strategy: :one_for_one, name: Discuss.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

**Step 5: 마이그레이션 복사**

```bash
cp priv/repo/migrations/20240326225108_create_topics.exs apps/discuss/priv/repo/migrations/
cp priv/repo/migrations/20240327182231_create_users.exs apps/discuss/priv/repo/migrations/
cp priv/repo/migrations/.formatter.exs apps/discuss/priv/repo/migrations/
```

**Step 6: seeds.exs 생성**

`apps/discuss/priv/repo/seeds.exs`:

```elixir
# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
```

**Step 7: test_helper.exs 작성**

`apps/discuss/test/test_helper.exs`:

```elixir
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Discuss.Repo, :manual)
```

**Step 8: DataCase 작성**

`apps/discuss/test/support/data_case.ex`:

```elixir
defmodule Discuss.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Discuss.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Discuss.DataCase
    end
  end

  setup tags do
    Discuss.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Discuss.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
```

**Step 9: .formatter.exs 작성**

`apps/discuss/.formatter.exs`:

```elixir
[
  import_deps: [:ecto, :ecto_sql],
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}", "priv/*/seeds.exs"],
  subdirectories: ["priv/*/migrations"]
]
```

**Step 10: 커밋**

```bash
git add apps/discuss/
git commit -m "refactor: apps/discuss 도메인 앱 생성 (Repo, Topics, Admin)"
```

---

## Task 3: apps/discuss_auth 앱 생성 (인증 컨텍스트)

phx.gen.auth 패턴 기반으로 Accounts 컨텍스트, User, UserToken 스키마를 직접 작성한다.

**Files:**
- Create: `apps/discuss_auth/mix.exs`
- Create: `apps/discuss_auth/lib/discuss_auth.ex`
- Create: `apps/discuss_auth/lib/discuss_auth/accounts.ex`
- Create: `apps/discuss_auth/lib/discuss_auth/accounts/user.ex`
- Create: `apps/discuss_auth/lib/discuss_auth/accounts/user_token.ex`
- Create: `apps/discuss_auth/lib/discuss_auth/accounts/user_notifier.ex`
- Create: `apps/discuss_auth/test/test_helper.exs`
- Create: `apps/discuss_auth/test/support/fixtures/accounts_fixtures.ex`
- Create: `apps/discuss_auth/test/discuss_auth/accounts_test.exs`
- Create: `apps/discuss_auth/.formatter.exs`
- Create: `apps/discuss/priv/repo/migrations/TIMESTAMP_create_accounts_users_auth_tables.exs`

**Step 1: 디렉토리 구조 생성**

```bash
mkdir -p apps/discuss_auth/lib/discuss_auth/accounts
mkdir -p apps/discuss_auth/test/support/fixtures
mkdir -p apps/discuss_auth/test/discuss_auth
```

**Step 2: apps/discuss_auth/mix.exs 작성**

```elixir
defmodule DiscussAuth.MixProject do
  use Mix.Project

  def project do
    [
      app: :discuss_auth,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:discuss, in_umbrella: true},
      {:bcrypt_elixir, "~> 3.0"},
      {:ecto_sql, "~> 3.12"},
      {:jason, "~> 1.4"}
    ]
  end
end
```

**Step 3: lib/discuss_auth.ex 작성**

```elixir
defmodule DiscussAuth do
  @moduledoc """
  인증 관련 컨텍스트를 정의하는 바운디드 컨텍스트.
  """
end
```

**Step 4: User 스키마 작성**

`apps/discuss_auth/lib/discuss_auth/accounts/user.ex`:

```elixir
defmodule DiscussAuth.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "accounts_users" do
    field :email, :string
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime

    # 가상 필드 (DB에 저장되지 않음)
    field :password, :string, virtual: true, redact: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  회원가입용 changeset. 이메일과 비밀번호를 검증한다.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email(opts)
    |> validate_password(opts)
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "올바른 이메일 형식이 아닙니다")
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Discuss.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  @doc """
  이메일 변경용 changeset.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "변경사항이 없습니다")
    end
  end

  @doc """
  비밀번호 변경용 changeset.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "비밀번호가 일치하지 않습니다")
    |> validate_password(opts)
  end

  @doc """
  이메일 인증 확인 changeset.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  비밀번호가 유효한지 검증한다.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  비밀번호 변경 후 세션 토큰 무효화를 위한 검증.
  """
  def validate_current_password(changeset, password) do
    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "올바르지 않습니다")
    end
  end
end
```

**Step 5: UserToken 스키마 작성**

`apps/discuss_auth/lib/discuss_auth/accounts/user_token.ex`:

```elixir
defmodule DiscussAuth.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32

  # 세션 토큰 유효 기간: 60일
  @session_validity_in_days 60

  schema "accounts_users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, DiscussAuth.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  세션 토큰을 생성한다.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: token, context: "session", user_id: user.id}}
  end

  @doc """
  세션 토큰으로 사용자를 조회하는 쿼리.
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  @doc """
  토큰과 컨텍스트로 조회하는 쿼리.
  """
  def by_token_and_context_query(token, context) do
    from __MODULE__, where: [token: ^token, context: ^context]
  end

  @doc """
  사용자의 특정 컨텍스트 토큰을 모두 조회하는 쿼리.
  """
  def by_user_and_contexts_query(user, :all) do
    from t in __MODULE__, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in __MODULE__, where: t.user_id == ^user.id and t.context in ^contexts
  end
end
```

**Step 6: UserNotifier 작성**

`apps/discuss_auth/lib/discuss_auth/accounts/user_notifier.ex`:

```elixir
defmodule DiscussAuth.Accounts.UserNotifier do
  import Swoosh.Email

  alias Discuss.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Discuss", "noreply@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  회원가입 확인 이메일.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "이메일 인증 안내", """
    안녕하세요, #{user.email}님,

    아래 링크를 클릭하여 계정을 인증해주세요:

    #{url}

    이 요청을 하지 않으셨다면 이 이메일을 무시해주세요.
    """)
  end

  @doc """
  비밀번호 재설정 이메일.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "비밀번호 재설정", """
    안녕하세요, #{user.email}님,

    아래 링크를 클릭하여 비밀번호를 재설정해주세요:

    #{url}

    이 요청을 하지 않으셨다면 이 이메일을 무시해주세요.
    """)
  end
end
```

**Step 7: Accounts 컨텍스트 작성**

`apps/discuss_auth/lib/discuss_auth/accounts.ex`:

```elixir
defmodule DiscussAuth.Accounts do
  @moduledoc """
  인증 관련 비즈니스 로직을 캡슐화하는 Accounts 컨텍스트.
  """

  import Ecto.Query
  alias Discuss.Repo
  alias DiscussAuth.Accounts.{User, UserToken, UserNotifier}

  ## 사용자 조회

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  def get_user!(id), do: Repo.get!(User, id)

  ## 회원가입

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## 설정 변경

  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## 세션 관리

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end
end
```

**Step 8: 인증 마이그레이션 작성**

`apps/discuss/priv/repo/migrations/20260225000001_create_accounts_users_auth_tables.exs`:

```elixir
defmodule Discuss.Repo.Migrations.CreateAccountsUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:accounts_users) do
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounts_users, [:email])

    create table(:accounts_users_tokens) do
      add :user_id, references(:accounts_users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:accounts_users_tokens, [:user_id])
    create unique_index(:accounts_users_tokens, [:context, :token])
  end
end
```

**Step 9: 테스트 파일 작성**

`apps/discuss_auth/test/test_helper.exs`:

```elixir
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Discuss.Repo, :manual)
```

`apps/discuss_auth/test/support/fixtures/accounts_fixtures.ex`:

```elixir
defmodule DiscussAuth.AccountsFixtures do
  @moduledoc """
  Accounts 컨텍스트용 테스트 픽스처.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello_world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> DiscussAuth.Accounts.register_user()

    user
  end
end
```

`apps/discuss_auth/test/discuss_auth/accounts_test.exs`:

```elixir
defmodule DiscussAuth.AccountsTest do
  use Discuss.DataCase

  alias DiscussAuth.Accounts

  import DiscussAuth.AccountsFixtures

  describe "register_user/1" do
    test "유효한 데이터로 사용자를 등록한다" do
      attrs = valid_user_attributes()
      assert {:ok, user} = Accounts.register_user(attrs)
      assert user.email == attrs.email
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end

    test "이메일이 없으면 에러를 반환한다" do
      assert {:error, changeset} = Accounts.register_user(%{password: valid_user_password()})
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "비밀번호가 8자 미만이면 에러를 반환한다" do
      attrs = valid_user_attributes(%{password: "short"})
      assert {:error, changeset} = Accounts.register_user(attrs)
      assert %{password: [msg]} = errors_on(changeset)
      assert msg =~ "at least"
    end

    test "중복 이메일은 에러를 반환한다" do
      %{email: email} = user_fixture()
      assert {:error, changeset} = Accounts.register_user(%{email: email, password: valid_user_password()})
      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "유효한 자격 증명으로 사용자를 반환한다" do
      %{id: id} = user_fixture()
      assert %{id: ^id} = Accounts.get_user_by_email_and_password(
        unique_user_email() |> then(fn _ -> user_fixture().email end) |> then(fn _ -> nil end),
        valid_user_password()
      )
    end
  end

  describe "generate_user_session_token/1" do
    test "세션 토큰을 생성한다" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert is_binary(token)
      assert byte_size(token) == 32
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "유효한 토큰으로 사용자를 반환한다", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "잘못된 토큰으로는 nil을 반환한다" do
      refute Accounts.get_user_by_session_token(:crypto.strong_rand_bytes(32))
    end
  end
end
```

**Step 10: .formatter.exs 작성**

`apps/discuss_auth/.formatter.exs`:

```elixir
[
  import_deps: [:ecto, :ecto_sql],
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}"]
]
```

**Step 11: 커밋**

```bash
git add apps/discuss_auth/ apps/discuss/priv/repo/migrations/20260225000001_create_accounts_users_auth_tables.exs
git commit -m "feat: apps/discuss_auth 인증 앱 생성 (Accounts, User, UserToken)"
```

---

## Task 4: apps/discuss_web 앱 생성 (Phoenix 웹 계층)

기존 웹 계층 코드를 discuss_web 앱으로 이전한다.

**Files:**
- Create: `apps/discuss_web/mix.exs`
- Move: `lib/discuss_web.ex` → `apps/discuss_web/lib/discuss_web.ex`
- Move: `lib/discuss_web/endpoint.ex`
- Move: `lib/discuss_web/router.ex`
- Move: `lib/discuss_web/telemetry.ex`
- Move: `lib/discuss_web/gettext.ex`
- Move: `lib/discuss_web/controllers/*`
- Move: `lib/discuss_web/components/*`
- Move: `assets/` → `apps/discuss_web/assets/`
- Move: `priv/static/` → `apps/discuss_web/priv/static/`
- Create: `apps/discuss_web/test/test_helper.exs`
- Create: `apps/discuss_web/test/support/conn_case.ex`
- Create: `apps/discuss_web/.formatter.exs`

**Step 1: 디렉토리 구조 생성**

```bash
mkdir -p apps/discuss_web/lib/discuss_web/controllers/topic_html
mkdir -p apps/discuss_web/lib/discuss_web/controllers/page_html
mkdir -p apps/discuss_web/lib/discuss_web/components/layouts
mkdir -p apps/discuss_web/test/support
mkdir -p apps/discuss_web/test/discuss_web/controllers
mkdir -p apps/discuss_web/priv/static
mkdir -p apps/discuss_web/priv/gettext
```

**Step 2: apps/discuss_web/mix.exs 작성**

```elixir
defmodule DiscussWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :discuss_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {DiscussWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:discuss, in_umbrella: true},
      {:discuss_auth, in_umbrella: true},
      {:phoenix, "~> 1.7.21"},
      {:phoenix_ecto, "~> 4.6"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.0.10"},
      {:floki, "~> 0.37.1", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.7"},
      {:esbuild, "~> 0.9", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3.1", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.2"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.6"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      test: ["test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind discuss_web", "esbuild discuss_web"],
      "assets.deploy": [
        "tailwind discuss_web --minify",
        "esbuild discuss_web --minify",
        "phx.digest"
      ]
    ]
  end
end
```

**Step 3: Application 모듈 작성**

`apps/discuss_web/lib/discuss_web/application.ex`:

```elixir
defmodule DiscussWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DiscussWeb.Telemetry,
      DiscussWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: DiscussWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    DiscussWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
```

**Step 4: 기존 웹 파일들 복사**

기존 파일들을 apps/discuss_web/ 로 복사 (내용 유지):

- `lib/discuss_web.ex` → `apps/discuss_web/lib/discuss_web.ex`
- `lib/discuss_web/endpoint.ex` → `apps/discuss_web/lib/discuss_web/endpoint.ex`
  (단, `otp_app: :discuss` → `otp_app: :discuss_web` 로 변경)
- `lib/discuss_web/telemetry.ex` → `apps/discuss_web/lib/discuss_web/telemetry.ex`
- `lib/discuss_web/gettext.ex` → `apps/discuss_web/lib/discuss_web/gettext.ex`
- `lib/discuss_web/controllers/*.ex` → 각각 동일 경로로
- `lib/discuss_web/controllers/topic_html/*.heex` → 동일 경로
- `lib/discuss_web/controllers/page_html/*.heex` → 동일 경로
- `lib/discuss_web/components/*.ex` → 동일 경로
- `lib/discuss_web/components/layouts/*.heex` → 동일 경로
- `assets/` → `apps/discuss_web/assets/`
- `priv/static/` → `apps/discuss_web/priv/static/`
- `priv/gettext/` → `apps/discuss_web/priv/gettext/`

**Step 5: endpoint.ex 수정 (otp_app 변경)**

`apps/discuss_web/lib/discuss_web/endpoint.ex`에서:

```elixir
use Phoenix.Endpoint, otp_app: :discuss_web
```

그리고 `Plug.Static` 부분:

```elixir
plug Plug.Static,
  at: "/",
  from: :discuss_web,
  gzip: false,
  only: DiscussWeb.static_paths()
```

그리고 `Phoenix.Ecto.CheckRepoStatus`:

```elixir
plug Phoenix.Ecto.CheckRepoStatus, otp_app: :discuss
```

**Step 6: config/config.exs 업데이트**

config 파일들에서 endpoint 설정의 otp_app을 `discuss_web`으로 변경:

`config/config.exs`:

```elixir
import Config

# Discuss 도메인 앱 설정
config :discuss,
  ecto_repos: [Discuss.Repo],
  generators: [timestamp_type: :utc_datetime]

# DiscussWeb 엔드포인트 설정
config :discuss_web, DiscussWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DiscussWeb.ErrorHTML, json: DiscussWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Discuss.PubSub,
  live_view: [signing_salt: "ZGAkxwtt"]

# Mailer 설정
config :discuss, Discuss.Mailer, adapter: Swoosh.Adapters.Local

# esbuild 설정
config :esbuild,
  version: "0.17.11",
  discuss_web: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/discuss_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# tailwind 설정
config :tailwind,
  version: "3.4.0",
  discuss_web: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../apps/discuss_web/assets", __DIR__)
  ]

# Logger 설정
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
```

`config/dev.exs`:

```elixir
import Config

config :discuss, Discuss.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "discuss_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :discuss_web, DiscussWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "1DYEwKRZwURUNAxbQwJ3jYg8fEFwEl65vNMiRDyHJ4ELom9uYG0QHKmAS+FMyzIR",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:discuss_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:discuss_web, ~w(--watch)]}
  ]

config :discuss_web, DiscussWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"apps/discuss_web/priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"apps/discuss_web/priv/gettext/.*(po)$",
      ~r"apps/discuss_web/lib/discuss_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :discuss_web, dev_routes: true

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, :debug_heex_annotations, true
config :swoosh, :api_client, false
```

`config/test.exs`:

```elixir
import Config

config :discuss, Discuss.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "discuss_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :discuss_web, DiscussWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "5UeJW+ZstZNciK1pcrV/yIv1fF7tcjmotPNPz3LOi02vIq0fVJBiGH2u7czpfSuo",
  server: false

config :discuss, Discuss.Mailer, adapter: Swoosh.Adapters.Test
config :swoosh, :api_client, false
config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
```

`config/prod.exs`:

```elixir
import Config

config :discuss_web, DiscussWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json"

config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: Discuss.Finch
config :swoosh, local: false
config :logger, level: :info
```

`config/runtime.exs`:

```elixir
import Config

if System.get_env("PHX_SERVER") do
  config :discuss_web, DiscussWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :discuss, Discuss.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :discuss, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :discuss_web, DiscussWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end
```

**Step 7: ConnCase 작성**

`apps/discuss_web/test/support/conn_case.ex`:

```elixir
defmodule DiscussWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint DiscussWeb.Endpoint

      use DiscussWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import DiscussWeb.ConnCase
    end
  end

  setup tags do
    Discuss.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
```

`apps/discuss_web/test/test_helper.exs`:

```elixir
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Discuss.Repo, :manual)
```

**Step 8: .formatter.exs 작성**

`apps/discuss_web/.formatter.exs`:

```elixir
[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"]
]
```

**Step 9: 기존 루트 lib/ 디렉토리 제거**

```bash
rm -rf lib/
```

**Step 10: 기존 루트 test/ 디렉토리 제거 (apps/ 로 이전 완료)**

```bash
rm -rf test/
rm -rf priv/
rm -rf assets/
```

**Step 11: 커밋**

```bash
git add apps/discuss_web/ config/ -A
git commit -m "refactor: apps/discuss_web 웹 앱 생성 및 config 업데이트"
```

---

## Task 5: 인증 웹 계층 추가 (컨트롤러, Plug, 템플릿)

discuss_web에 인증 관련 컨트롤러, Plug, 템플릿을 추가한다.

**Files:**
- Create: `apps/discuss_web/lib/discuss_web/controllers/user_session_controller.ex`
- Create: `apps/discuss_web/lib/discuss_web/controllers/user_registration_controller.ex`
- Create: `apps/discuss_web/lib/discuss_web/controllers/user_session_html.ex`
- Create: `apps/discuss_web/lib/discuss_web/controllers/user_registration_html.ex`
- Create: `apps/discuss_web/lib/discuss_web/controllers/user_session_html/new.html.heex`
- Create: `apps/discuss_web/lib/discuss_web/controllers/user_registration_html/new.html.heex`
- Create: `apps/discuss_web/lib/discuss_web/auth/user_auth.ex`
- Modify: `apps/discuss_web/lib/discuss_web/router.ex`
- Modify: `apps/discuss_web/lib/discuss_web/components/layouts/root.html.heex`

**Step 1: UserAuth Plug 작성**

`apps/discuss_web/lib/discuss_web/auth/user_auth.ex`:

```elixir
defmodule DiscussWeb.UserAuth do
  @moduledoc """
  인증 관련 Plug 함수들.
  """

  use DiscussWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias DiscussAuth.Accounts

  # 세션 유효 기간 (초): 60일
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_discuss_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  사용자를 로그인 처리한다.
  """
  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  사용자를 로그아웃 처리한다.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      DiscussWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  현재 사용자를 conn.assigns에 할당하는 Plug.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  인증된 사용자만 접근을 허용하는 Plug.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "로그인이 필요합니다.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end

  @doc """
  비인증 사용자만 접근을 허용하는 Plug (로그인/회원가입 페이지용).
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: ~p"/topics"
end
```

**Step 2: UserSessionController 작성**

`apps/discuss_web/lib/discuss_web/controllers/user_session_controller.ex`:

```elixir
defmodule DiscussWeb.UserSessionController do
  use DiscussWeb, :controller

  alias DiscussAuth.Accounts
  alias DiscussWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error_message: nil)
  end

  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, "로그인되었습니다.")
      |> UserAuth.log_in_user(user, user_params)
    else
      render(conn, :new, error_message: "이메일 또는 비밀번호가 올바르지 않습니다.")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "로그아웃되었습니다.")
    |> UserAuth.log_out_user()
  end
end
```

**Step 3: UserRegistrationController 작성**

`apps/discuss_web/lib/discuss_web/controllers/user_registration_controller.ex`:

```elixir
defmodule DiscussWeb.UserRegistrationController do
  use DiscussWeb, :controller

  alias DiscussAuth.Accounts
  alias DiscussAuth.Accounts.User
  alias DiscussWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "계정이 생성되었습니다.")
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
```

**Step 4: 로그인 템플릿 작성**

`apps/discuss_web/lib/discuss_web/controllers/user_session_html.ex`:

```elixir
defmodule DiscussWeb.UserSessionHTML do
  use DiscussWeb, :html

  embed_templates "user_session_html/*"
end
```

`apps/discuss_web/lib/discuss_web/controllers/user_session_html/new.html.heex`:

```heex
<div class="mx-auto max-w-sm mt-10">
  <div class="bg-white shadow-md rounded-lg px-8 pt-6 pb-8 mb-4">
    <h2 class="text-2xl font-bold text-center text-gray-800 mb-6">로그인</h2>

    <%= if @error_message do %>
      <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded relative mb-4" role="alert">
        <span class="block sm:inline"><%= @error_message %></span>
      </div>
    <% end %>

    <.simple_form :let={f} for={%{}} as={:user} action={~p"/users/log_in"}>
      <.input field={f[:email]} type="email" label="이메일" required />
      <.input field={f[:password]} type="password" label="비밀번호" required />

      <div class="flex items-center justify-between mt-4">
        <label class="flex items-center">
          <input type="checkbox" name="user[remember_me]" value="true" class="rounded border-gray-300 text-indigo-600 shadow-sm focus:ring-indigo-500" />
          <span class="ml-2 text-sm text-gray-600">로그인 유지</span>
        </label>
      </div>

      <:actions>
        <.button phx-disable-with="로그인 중..." class="w-full bg-indigo-600 hover:bg-indigo-700">
          로그인
        </.button>
      </:actions>
    </.simple_form>

    <p class="text-center text-sm text-gray-600 mt-4">
      계정이 없으신가요?
      <.link navigate={~p"/users/register"} class="font-semibold text-indigo-600 hover:text-indigo-500">
        회원가입
      </.link>
    </p>
  </div>
</div>
```

**Step 5: 회원가입 템플릿 작성**

`apps/discuss_web/lib/discuss_web/controllers/user_registration_html.ex`:

```elixir
defmodule DiscussWeb.UserRegistrationHTML do
  use DiscussWeb, :html

  embed_templates "user_registration_html/*"
end
```

`apps/discuss_web/lib/discuss_web/controllers/user_registration_html/new.html.heex`:

```heex
<div class="mx-auto max-w-sm mt-10">
  <div class="bg-white shadow-md rounded-lg px-8 pt-6 pb-8 mb-4">
    <h2 class="text-2xl font-bold text-center text-gray-800 mb-6">회원가입</h2>

    <.simple_form :let={f} for={@changeset} action={~p"/users/register"}>
      <.error :if={@changeset.action}>
        오류가 발생했습니다. 아래 내용을 확인해주세요.
      </.error>

      <.input field={f[:email]} type="email" label="이메일" required />
      <.input field={f[:password]} type="password" label="비밀번호" required />

      <:actions>
        <.button phx-disable-with="계정 생성 중..." class="w-full bg-indigo-600 hover:bg-indigo-700">
          회원가입
        </.button>
      </:actions>
    </.simple_form>

    <p class="text-center text-sm text-gray-600 mt-4">
      이미 계정이 있으신가요?
      <.link navigate={~p"/users/log_in"} class="font-semibold text-indigo-600 hover:text-indigo-500">
        로그인
      </.link>
    </p>
  </div>
</div>
```

**Step 6: Router 업데이트 (인증 경로 추가)**

`apps/discuss_web/lib/discuss_web/router.ex`:

```elixir
defmodule DiscussWeb.Router do
  use DiscussWeb, :router

  import DiscussWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DiscussWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # 공개 경로
  scope "/", DiscussWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # 비인증 사용자 전용 경로 (로그인/회원가입)
  scope "/", DiscussWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
  end

  # 인증 필수 경로
  scope "/", DiscussWeb do
    pipe_through [:browser, :require_authenticated_user]

    # 토픽 관련 경로
    get "/topics", TopicController, :index
    get "/topics/new", TopicController, :new
    post "/topics", TopicController, :create
    get "/topics/:id", TopicController, :show
    get "/topics/:id/edit", TopicController, :edit
    put "/topics/:id", TopicController, :update
    delete "/topics/:id", TopicController, :delete
  end

  # 로그아웃 (인증된 사용자)
  scope "/", DiscussWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete
  end

  scope "/api", DiscussWeb do
    pipe_through :api
  end

  if Application.compile_env(:discuss_web, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DiscussWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
```

**Step 7: 네비게이션 바 업데이트 (로그인/로그아웃 표시)**

`apps/discuss_web/lib/discuss_web/components/layouts/root.html.heex`의 네비게이션에 현재 사용자 정보를 표시:

nav 요소 내 `justify-between` div 안에 오른쪽 영역을 추가:

```heex
<!-- 기존 네비게이션의 오른쪽 영역에 추가 -->
<div class="hidden md:block">
  <div class="ml-4 flex items-center md:ml-6">
    <%= if @current_user do %>
      <span class="text-indigo-200 text-sm mr-4">
        <%= @current_user.email %>
      </span>
      <.link
        href={~p"/users/log_out"}
        method="delete"
        class="text-white hover:bg-indigo-500 hover:bg-opacity-75 px-3 py-2 rounded-md text-sm font-medium"
      >
        로그아웃
      </.link>
    <% else %>
      <.link
        href={~p"/users/log_in"}
        class="text-white hover:bg-indigo-500 hover:bg-opacity-75 px-3 py-2 rounded-md text-sm font-medium"
      >
        로그인
      </.link>
      <.link
        href={~p"/users/register"}
        class="ml-2 bg-white text-indigo-600 hover:bg-indigo-50 px-3 py-2 rounded-md text-sm font-medium"
      >
        회원가입
      </.link>
    <% end %>
  </div>
</div>
```

주의: `root.html.heex`에서 `@current_user`를 사용하려면 `endpoint.ex`에서 `:fetch_current_user` plug이 router pipeline에 있으므로, 레이아웃에 전달되는 assigns에 포함됩니다.

**Step 8: 커밋**

```bash
git add apps/discuss_web/
git commit -m "feat: 회원가입/로그인 컨트롤러, Plug, 템플릿 추가"
```

---

## Task 6: FK 마이그레이션 및 스키마 연관관계 추가

topics 테이블에 auth_user_id FK를 추가하고, users 테이블에도 auth_user_id FK를 추가한다.

**Files:**
- Create: `apps/discuss/priv/repo/migrations/20260225000002_add_auth_user_id_to_topics.exs`
- Create: `apps/discuss/priv/repo/migrations/20260225000003_add_auth_user_id_to_users.exs`
- Modify: `apps/discuss/lib/discuss/topics/topic.ex`
- Modify: `apps/discuss/lib/discuss/admin/user.ex`
- Modify: `apps/discuss_auth/lib/discuss_auth/accounts/user.ex`

**Step 1: topics 마이그레이션 작성**

`apps/discuss/priv/repo/migrations/20260225000002_add_auth_user_id_to_topics.exs`:

```elixir
defmodule Discuss.Repo.Migrations.AddAuthUserIdToTopics do
  use Ecto.Migration

  def change do
    alter table(:topics) do
      add :auth_user_id, references(:accounts_users, on_delete: :nilify_all)
    end

    create index(:topics, [:auth_user_id])
  end
end
```

**Step 2: users 마이그레이션 작성**

`apps/discuss/priv/repo/migrations/20260225000003_add_auth_user_id_to_users.exs`:

```elixir
defmodule Discuss.Repo.Migrations.AddAuthUserIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :auth_user_id, references(:accounts_users, on_delete: :nilify_all)
    end

    create index(:users, [:auth_user_id])
  end
end
```

**Step 3: Topic 스키마에 belongs_to 추가**

`apps/discuss/lib/discuss/topics/topic.ex`:

```elixir
defmodule Discuss.Topics.Topic do
  use Ecto.Schema
  import Ecto.Changeset

  schema "topics" do
    field :title, :string
    field :auth_user_id, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(topic, attrs) do
    topic
    |> cast(attrs, [:title, :auth_user_id])
    |> validate_required([:title])
    |> validate_length(:title, min: 2)
    |> validate_length(:title, max: 100)
  end
end
```

주의: `belongs_to`를 사용하지 않고 `field :auth_user_id, :integer`로 선언. discuss 앱이 discuss_auth에 의존하지 않도록 하기 위함 (의존성 방향: discuss_auth → discuss).

**Step 4: Admin.User 스키마에 auth_user_id 추가**

`apps/discuss/lib/discuss/admin/user.ex`:

```elixir
defmodule Discuss.Admin.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :role, :string
    field :address, :string
    field :auth_user_id, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :role, :address, :auth_user_id])
    |> validate_required([:name, :email, :role, :address])
    |> unique_constraint(:email)
  end
end
```

**Step 5: TopicController에 current_user 연결 로직 추가**

`apps/discuss_web/lib/discuss_web/controllers/topic_controller.ex`의 `create` 액션:

```elixir
def create(conn, %{"topic" => topic_params}) do
  topic_params = Map.put(topic_params, "auth_user_id", conn.assigns.current_user.id)

  case Topics.create_topic(topic_params) do
    {:ok, topic} ->
      conn
      |> put_flash(:info, "\"#{topic.title}\" 토픽이 생성되었습니다.")
      |> redirect(to: ~p"/topics")

    {:error, changeset} ->
      render(conn, :new, layout: false, changeset: changeset)
  end
end
```

**Step 6: 커밋**

```bash
git add apps/discuss/ apps/discuss_web/
git commit -m "feat: topics/users에 auth_user_id FK 추가 및 연관관계 설정"
```

---

## Task 7: 빌드 및 마이그레이션 검증

전체 엄브렐라 프로젝트가 컴파일되고 마이그레이션이 동작하는지 확인한다.

**Step 1: 의존성 설치**

```bash
cd /c/Users/mingy/github/mingyuchoo/elixir-study-series/Web/discuss
mix deps.get
```

Expected: 모든 의존성 (bcrypt_elixir 포함) 설치 성공

**Step 2: 컴파일**

```bash
mix compile
```

Expected: 경고 있을 수 있으나 에러 없이 컴파일 성공

**Step 3: DB 생성 및 마이그레이션**

```bash
mix ecto.create
mix ecto.migrate
```

Expected: discuss_dev 데이터베이스 생성, 4개 마이그레이션 (create_topics, create_users, create_accounts_users_auth_tables, add_auth_user_id_to_topics, add_auth_user_id_to_users) 성공

**Step 4: 테스트 실행**

```bash
mix test
```

Expected: 모든 테스트 통과

**Step 5: 개발 서버 실행 확인**

```bash
mix phx.server
```

Expected: http://localhost:4000 에서 정상 동작, /users/register, /users/log_in 페이지 접근 가능

**Step 6: 커밋**

```bash
git add -A
git commit -m "chore: 엄브렐라 프로젝트 빌드 및 마이그레이션 검증 완료"
```

---

## Task 8: README.md 업데이트

프로젝트 구조 변경에 맞춰 README를 업데이트한다.

**Files:**
- Modify: `README.md`

**Step 1: README.md 업데이트**

엄브렐라 구조, 3개 앱 설명, 인증 기능 추가를 반영한 README를 작성한다.

주요 변경사항:
- 프로젝트 구조를 엄브렐라 구조로 설명
- apps/discuss, apps/discuss_auth, apps/discuss_web 각 앱의 역할 설명
- 회원가입/로그인 기능 안내
- 개발/테스트 명령어 업데이트 (엄브렐라에 맞게)

**Step 2: 커밋**

```bash
git add README.md
git commit -m "docs: 엄브렐라 구조 및 인증 기능 반영하여 README 업데이트"
```

---

## 컴파일 시 주의사항

1. **config에서 `discuss` → `discuss_web` 변경**: Endpoint, live_reload, watchers 관련 config의 otp_app이 `discuss_web`으로 변경되어야 함
2. **esbuild/tailwind 프로필명**: `discuss` → `discuss_web`으로 변경
3. **assets 경로**: `../assets` → `../apps/discuss_web/assets`
4. **Plug.Static from**: `:discuss` → `:discuss_web`
5. **bcrypt_elixir**: NIF 컴파일이 필요하므로 C 컴파일러가 설치되어 있어야 함
6. **마이그레이션 순서**: timestamp 기반이므로 20240326... < 20240327... < 20260225... 순서로 실행됨
