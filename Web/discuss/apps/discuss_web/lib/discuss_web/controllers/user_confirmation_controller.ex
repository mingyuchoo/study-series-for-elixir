defmodule DiscussWeb.UserConfirmationController do
  use DiscussWeb, :controller

  alias DiscussAuth.Accounts

  def new(conn, _params) do
    render(conn, :new, layout: false)
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/users/confirm/#{&1}")
      )
    end

    conn
    |> put_flash(
      :info,
      "이메일 주소가 등록되어 있다면 인증 링크가 발송되었습니다. 받은 편지함을 확인해 주세요."
    )
    |> redirect(to: ~p"/")
  end

  def edit(conn, %{"token" => token}) do
    render(conn, :edit, layout: false, token: token)
  end

  def update(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "이메일 인증이 완료되었습니다.")
        |> redirect(to: ~p"/")

      :error ->
        conn
        |> put_flash(:error, "인증 링크가 유효하지 않거나 만료되었습니다.")
        |> redirect(to: ~p"/users/confirm")
    end
  end
end
