defmodule Auth.GuardianTest do
  use Auth.DataCase

  alias Auth.Guardian
  alias Playa.Accounts

  setup do
    # Create a test user
    {:ok, user} =
      Accounts.register_user(%{
        email: "test#{System.unique_integer()}@example.com",
        password: "hello world!"
      })

    %{user: user}
  end

  describe "subject_for_token/2" do
    test "returns user id as subject", %{user: user} do
      assert {:ok, subject} = Guardian.subject_for_token(user, %{})
      assert subject == to_string(user.id)
    end
  end

  describe "resource_from_claims/1" do
    test "returns user when valid sub claim is provided", %{user: user} do
      claims = %{"sub" => to_string(user.id)}
      assert {:ok, fetched_user} = Guardian.resource_from_claims(claims)
      assert fetched_user.id == user.id
      assert fetched_user.email == user.email
    end

    test "returns error when user does not exist" do
      claims = %{"sub" => "-1"}
      assert {:error, :resource_not_found} = Guardian.resource_from_claims(claims)
    end

    test "returns error when sub claim is missing" do
      claims = %{}
      assert {:error, :resource_not_found} = Guardian.resource_from_claims(claims)
    end
  end

  describe "encode_and_sign/2" do
    test "generates a valid token for user", %{user: user} do
      assert {:ok, token, claims} = Guardian.encode_and_sign(user)
      assert is_binary(token)
      assert claims["sub"] == to_string(user.id)
      assert claims["aud"] == "auth"
    end

    test "generated token can be decoded back to user", %{user: user} do
      {:ok, token, _claims} = Guardian.encode_and_sign(user)
      assert {:ok, decoded_user, _claims} = Guardian.resource_from_token(token)
      assert decoded_user.id == user.id
    end
  end

  describe "issue_access_token/1" do
    test "creates an access token with 60 second expiration", %{user: user} do
      current_time = System.system_time(:second)
      assert {:ok, _token, claims} = Guardian.issue_access_token(user)

      assert claims["typ"] == "access"
      assert claims["aud"] == "Auth"
      assert claims["exp"] >= current_time + 59
      assert claims["exp"] <= current_time + 61
    end

    test "access token includes user as subject", %{user: user} do
      assert {:ok, _token, claims} = Guardian.issue_access_token(user)
      assert claims["sub"] == to_string(user.id)
    end
  end

  describe "issue_refresh_token/1" do
    test "creates a refresh token with 24 hour expiration", %{user: user} do
      current_time = System.system_time(:second)
      expected_exp = 24 * 60 * 60

      assert {:ok, _token, claims} = Guardian.issue_refresh_token(user)

      assert claims["typ"] == "refresh"
      assert claims["aud"] == "Auth"
      assert claims["exp"] >= current_time + expected_exp - 1
      assert claims["exp"] <= current_time + expected_exp + 1
    end

    test "refresh token includes user as subject", %{user: user} do
      assert {:ok, _token, claims} = Guardian.issue_refresh_token(user)
      assert claims["sub"] == to_string(user.id)
    end
  end

  describe "encode_and_sign_with_ttl/2" do
    test "creates token with default 60 second TTL", %{user: user} do
      current_time = System.system_time(:second)
      assert {:ok, _token, claims} = Guardian.encode_and_sign_with_ttl(user)

      assert claims["exp"] >= current_time + 59
      assert claims["exp"] <= current_time + 61
    end

    test "creates token with custom TTL", %{user: user} do
      current_time = System.system_time(:second)
      custom_ttl = 300

      assert {:ok, _token, claims} = Guardian.encode_and_sign_with_ttl(user, custom_ttl)

      assert claims["exp"] >= current_time + custom_ttl - 1
      assert claims["exp"] <= current_time + custom_ttl + 1
    end

    test "token with custom TTL can be verified", %{user: user} do
      {:ok, token, _claims} = Guardian.encode_and_sign_with_ttl(user, 300)
      assert {:ok, decoded_user, _claims} = Guardian.resource_from_token(token)
      assert decoded_user.id == user.id
    end
  end

  describe "token expiration" do
    test "expired token returns error", %{user: user} do
      # Create a token with 0 second TTL (immediately expired)
      {:ok, token, _claims} = Guardian.encode_and_sign_with_ttl(user, -10)

      # Wait a moment to ensure token is expired
      Process.sleep(100)

      # Attempting to use expired token should fail
      assert {:error, _reason} = Guardian.resource_from_token(token)
    end

    test "valid token within TTL can be used", %{user: user} do
      {:ok, token, _claims} = Guardian.encode_and_sign_with_ttl(user, 60)
      assert {:ok, decoded_user, _claims} = Guardian.resource_from_token(token)
      assert decoded_user.id == user.id
    end
  end
end
