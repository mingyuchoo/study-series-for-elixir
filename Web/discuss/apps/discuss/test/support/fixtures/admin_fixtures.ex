defmodule Discuss.AdminFixtures do
  @moduledoc """
  Admin 컨텍스트용 테스트 픽스처.
  """

  def valid_admin_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      "name" => "관리자#{System.unique_integer([:positive])}",
      "email" => "admin#{System.unique_integer([:positive])}@example.com",
      "role" => "admin",
      "address" => "서울시 강남구"
    })
  end

  def admin_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_admin_user_attributes()
      |> Discuss.Admin.create_user()

    user
  end
end
