defmodule DiscussAuth.Accounts do
  @moduledoc """
  인증 관련 비즈니스 로직을 캡슐화하는 Accounts 컨텍스트.
  """

  alias Discuss.Repo
  alias DiscussAuth.Accounts.{User, UserToken}

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

  ## 이메일 인증

  @doc """
  이메일 인증 안내 이메일을 발송한다.
  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      Discuss.Mailer.deliver(
        Swoosh.Email.new()
        |> Swoosh.Email.to(user.email)
        |> Swoosh.Email.from({"토픽 관리 시스템", "noreply@discuss.local"})
        |> Swoosh.Email.subject("이메일 인증")
        |> Swoosh.Email.html_body("""
        <p>안녕하세요!</p>
        <p>아래 링크를 클릭하여 이메일을 인증해 주세요:</p>
        <p><a href="#{confirmation_url_fun.(encoded_token)}">이메일 인증하기</a></p>
        <p>이 링크는 7일 후 만료됩니다.</p>
        """)
      )

      {:ok, encoded_token}
    end
  end

  @doc """
  이메일 인증 토큰으로 사용자를 인증한다.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, ["confirm"])
    )
  end

  ## 비밀번호 재설정

  @doc """
  비밀번호 재설정 안내 이메일을 발송한다.
  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)

    Discuss.Mailer.deliver(
      Swoosh.Email.new()
      |> Swoosh.Email.to(user.email)
      |> Swoosh.Email.from({"토픽 관리 시스템", "noreply@discuss.local"})
      |> Swoosh.Email.subject("비밀번호 재설정")
      |> Swoosh.Email.html_body("""
      <p>안녕하세요!</p>
      <p>아래 링크를 클릭하여 비밀번호를 재설정해 주세요:</p>
      <p><a href="#{reset_password_url_fun.(encoded_token)}">비밀번호 재설정하기</a></p>
      <p>이 링크는 1일 후 만료됩니다.</p>
      <p>만약 비밀번호 재설정을 요청하지 않으셨다면 이 이메일을 무시하시기 바랍니다.</p>
      """)
    )

    {:ok, encoded_token}
  end

  @doc """
  비밀번호 재설정 토큰으로 사용자를 조회한다.
  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  비밀번호를 재설정한다.
  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end
end
