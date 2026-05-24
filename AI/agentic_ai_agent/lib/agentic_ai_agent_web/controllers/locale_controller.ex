defmodule AgenticAiAgentWeb.LocaleController do
  use AgenticAiAgentWeb, :controller

  alias AgenticAiAgent.Accounts
  alias AgenticAiAgentWeb.Locale

  @one_year_seconds 60 * 60 * 24 * 365

  def set(conn, %{"locale" => locale} = params) do
    locale =
      if locale in Locale.supported(), do: locale, else: Locale.default()

    return_to = safe_return_to(params["return_to"])

    maybe_store_locale(conn.assigns[:current_user], locale)

    conn
    |> put_resp_cookie("app_locale", locale,
      max_age: @one_year_seconds,
      same_site: "Lax",
      http_only: false
    )
    |> put_session(:locale, locale)
    |> redirect(to: return_to)
  end

  # Only allow same-origin internal paths.
  defp safe_return_to(nil), do: "/"
  defp safe_return_to("/" <> _ = path), do: path
  defp safe_return_to(_), do: "/"

  defp maybe_store_locale(nil, _locale), do: :ok

  defp maybe_store_locale(user, locale) do
    Accounts.update_user_preferences(user, %{
      preferred_locale: locale,
      preferred_theme: user.preferred_theme || "system"
    })

    :ok
  end
end
