defmodule DiscussWeb.UserPasswordResetController do
  use DiscussWeb, :controller

  alias DiscussAuth.Accounts

  def new(conn, _params) do
    render(conn, :new, layout: false)
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset_password/#{&1}")
      )
    end

    conn
    |> put_flash(
      :info,
      "이메일 주소가 등록되어 있다면 비밀번호 재설정 링크가 발송되었습니다."
    )
    |> redirect(to: ~p"/users/log_in")
  end

  def edit(conn, %{"token" => token}) do
    user = Accounts.get_user_by_reset_password_token(token)

    if user do
      changeset = Accounts.change_user_password(user)
      render(conn, :edit, layout: false, changeset: changeset, token: token)
    else
      conn
      |> put_flash(:error, "비밀번호 재설정 링크가 유효하지 않거나 만료되었습니다.")
      |> redirect(to: ~p"/users/reset_password")
    end
  end

  def update(conn, %{"token" => token, "user" => user_params}) do
    user = Accounts.get_user_by_reset_password_token(token)

    if user do
      case Accounts.reset_user_password(user, user_params) do
        {:ok, _} ->
          conn
          |> put_flash(:info, "비밀번호가 성공적으로 재설정되었습니다.")
          |> redirect(to: ~p"/users/log_in")

        {:error, changeset} ->
          render(conn, :edit, layout: false, changeset: changeset, token: token)
      end
    else
      conn
      |> put_flash(:error, "비밀번호 재설정 링크가 유효하지 않거나 만료되었습니다.")
      |> redirect(to: ~p"/users/reset_password")
    end
  end
end
