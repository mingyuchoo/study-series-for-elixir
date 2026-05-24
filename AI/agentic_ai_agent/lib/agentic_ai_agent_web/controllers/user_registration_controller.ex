defmodule AgenticAiAgentWeb.UserRegistrationController do
  use AgenticAiAgentWeb, :controller

  alias AgenticAiAgent.Accounts
  alias AgenticAiAgent.Accounts.User
  alias AgenticAiAgentWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, changeset: User.registration_changeset(%User{}, %{}))
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, gettext("Account created."))
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:new, changeset: changeset)
    end
  end
end
