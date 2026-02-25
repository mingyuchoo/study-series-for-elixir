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

  @doc """
  인증된 상태의 conn을 생성하는 헬퍼.
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = DiscussAuth.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  def log_in_user(conn, user) do
    token = DiscussAuth.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
