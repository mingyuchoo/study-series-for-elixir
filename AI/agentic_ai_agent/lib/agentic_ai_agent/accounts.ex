defmodule AgenticAiAgent.Accounts do
  @moduledoc """
  User accounts and password authentication.
  """

  import Ecto.Query

  alias AgenticAiAgent.Accounts.User
  alias AgenticAiAgent.Repo

  @hash_algorithm :sha256
  @hash_iterations 210_000
  @hash_length 32

  def get_user(id) when is_binary(id), do: Repo.get(User, id)
  def get_user(_), do: nil

  def get_user_by_email(email) when is_binary(email) do
    normalized = normalize_email(email)
    Repo.one(from u in User, where: u.email == ^normalized)
  end

  def create_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_user_profile(%User{} = user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  def update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  def update_user_preferences(%User{} = user, attrs) do
    user
    |> User.preferences_changeset(attrs)
    |> Repo.update()
  end

  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

    cond do
      user && verify_password(password, user.password_hash) ->
        {:ok, user}

      true ->
        {:error, :invalid_credentials}
    end
  end

  def hash_password(password) when is_binary(password) do
    salt = :crypto.strong_rand_bytes(16)

    hash =
      :crypto.pbkdf2_hmac(@hash_algorithm, password, salt, @hash_iterations, @hash_length)

    [
      "pbkdf2_sha256",
      Integer.to_string(@hash_iterations),
      Base.url_encode64(salt, padding: false),
      Base.url_encode64(hash, padding: false)
    ]
    |> Enum.join("$")
  end

  def verify_password(password, encoded) when is_binary(password) and is_binary(encoded) do
    with ["pbkdf2_sha256", iterations, salt64, hash64] <- String.split(encoded, "$"),
         {iterations, ""} <- Integer.parse(iterations),
         {:ok, salt} <- Base.url_decode64(salt64, padding: false),
         {:ok, expected} <- Base.url_decode64(hash64, padding: false) do
      actual =
        :crypto.pbkdf2_hmac(@hash_algorithm, password, salt, iterations, byte_size(expected))

      Plug.Crypto.secure_compare(actual, expected)
    else
      _ -> false
    end
  end

  def verify_password(_, _), do: false

  defp normalize_email(email), do: email |> String.trim() |> String.downcase()
end
