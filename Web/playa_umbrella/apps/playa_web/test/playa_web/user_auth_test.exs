defmodule PlayaWeb.UserAuthTest do
  use PlayaWeb.ConnCase, async: true

  import Playa.AccountsFixtures

  # @remember_me_cookie "_playa_web_user_remember_me"

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, PlayaWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{user: user_fixture(), conn: conn}
  end

  describe "log_in_user/3" do
    # TODO:
  end
end
