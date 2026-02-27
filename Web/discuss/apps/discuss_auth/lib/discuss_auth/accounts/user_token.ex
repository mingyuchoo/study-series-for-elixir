defmodule DiscussAuth.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  @rand_size 32
  @hash_algorithm :sha256
  @session_validity_in_days 60
  @confirmation_validity_in_days 7
  @reset_password_validity_in_days 1

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
  이메일 토큰을 생성한다 (이메일 인증, 비밀번호 재설정 등).
  """
  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
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
  이메일 토큰으로 사용자를 조회하는 쿼리.
  """
  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        days = days_for_context(context)

        query =
          from t in by_token_and_context_query(hashed_token, context),
            join: user in assoc(t, :user),
            where: t.inserted_at > ago(^days, "day") and t.sent_to == user.email,
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  defp days_for_context("confirm"), do: @confirmation_validity_in_days
  defp days_for_context("reset_password"), do: @reset_password_validity_in_days

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
