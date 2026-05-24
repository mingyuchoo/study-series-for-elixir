defmodule AgenticAiAgentWeb.UserSessionController do
  use AgenticAiAgentWeb, :controller

  alias AgenticAiAgent.Accounts
  alias AgenticAiAgentWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error_message: nil, return_to: get_session(conn, :user_return_to))
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user, user_params)

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:error, gettext("Invalid email or password."))
        |> put_status(:unprocessable_entity)
        |> render(:new,
          error_message: gettext("Invalid email or password."),
          return_to: get_session(conn, :user_return_to)
        )
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, gettext("Invalid email or password."))
    |> put_status(:unprocessable_entity)
    |> render(:new,
      error_message: gettext("Invalid email or password."),
      return_to: get_session(conn, :user_return_to)
    )
  end

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end
end
