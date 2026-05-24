defmodule AgenticAiAgentWeb.UserAuth do
  use AgenticAiAgentWeb, :verified_routes

  import Phoenix.Controller
  import Plug.Conn

  alias AgenticAiAgent.Accounts

  @session_key :user_id

  def init(action), do: action
  def call(conn, action), do: apply(__MODULE__, action, [conn, []])

  def fetch_current_user(conn, _opts) do
    user = Accounts.get_user(get_session(conn, @session_key))
    Plug.Conn.assign(conn, :current_user, user)
  end

  def log_in_user(conn, user, params \\ %{}) do
    return_to = non_blank(params["return_to"]) || get_session(conn, :user_return_to) || ~p"/chat"

    conn
    |> renew_session()
    |> put_session(@session_key, user.id)
    |> put_session(:locale, user.preferred_locale || AgenticAiAgentWeb.Locale.default())
    |> put_session(:theme, user.preferred_theme || "system")
    |> delete_session(:user_return_to)
    |> redirect(to: return_to)
  end

  def log_out_user(conn) do
    conn
    |> renew_session()
    |> put_flash(:info, "Logged out.")
    |> redirect(to: ~p"/login")
  end

  def redirect_if_user_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: ~p"/chat")
      |> halt()
    else
      conn
    end
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_session(:user_return_to, current_path(conn))
      |> put_flash(:error, "Log in to continue.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case Accounts.get_user(session[to_string(@session_key)]) do
      nil ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "Log in to continue.")
          |> Phoenix.LiveView.redirect(to: ~p"/login")

        {:halt, socket}

      user ->
        socket =
          socket
          |> Phoenix.Component.assign(:current_user, user)
          |> Phoenix.LiveView.push_event("set-saved-theme", %{
            theme: user.preferred_theme || "system"
          })

        {:cont, socket}
    end
  end

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont,
     Phoenix.Component.assign(
       socket,
       :current_user,
       Accounts.get_user(session[to_string(@session_key)])
     )}
  end

  defp renew_session(conn) do
    locale = get_session(conn, :locale)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> maybe_keep_locale(locale)
  end

  defp maybe_keep_locale(conn, nil), do: conn
  defp maybe_keep_locale(conn, locale), do: put_session(conn, :locale, locale)

  defp non_blank(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp non_blank(_), do: nil
end
