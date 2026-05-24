defmodule AgenticAiAgentWeb.PreferenceController do
  use AgenticAiAgentWeb, :controller

  alias AgenticAiAgent.Accounts

  @themes ~w(system light dark)

  def theme(conn, %{"theme" => theme}) when theme in @themes do
    user = conn.assigns.current_user

    Accounts.update_user_preferences(user, %{
      preferred_locale: user.preferred_locale || AgenticAiAgentWeb.Locale.default(),
      preferred_theme: theme
    })

    send_resp(conn, :no_content, "")
  end

  def theme(conn, _params), do: send_resp(conn, :unprocessable_entity, "")
end
