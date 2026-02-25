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
