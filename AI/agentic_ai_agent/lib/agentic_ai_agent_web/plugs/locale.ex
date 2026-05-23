defmodule AgenticAiAgentWeb.Plugs.Locale do
  @moduledoc """
  Selects the active locale for the current request and pushes it into both
  the Gettext process dictionary and the Plug session so LiveView mounts can
  read it back.

  Resolution order:

    1. `?locale=ko` query param (one-shot override; not persisted)
    2. `app_locale` cookie (set by `LocaleController`)
    3. `Accept-Language` header
    4. The default locale (`en`).
  """

  import Plug.Conn

  @behaviour Plug

  @supported AgenticAiAgentWeb.Locale.supported()
  @default AgenticAiAgentWeb.Locale.default()

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    locale =
      pick_from_query(conn) ||
        pick_from_cookie(conn) ||
        pick_from_header(conn) ||
        @default

    Gettext.put_locale(AgenticAiAgentWeb.Gettext, locale)
    put_session(conn, :locale, locale)
  end

  defp pick_from_query(%Plug.Conn{params: %{"locale" => l}}) when l in @supported, do: l
  defp pick_from_query(_), do: nil

  defp pick_from_cookie(conn) do
    case conn.cookies["app_locale"] do
      l when l in @supported -> l
      _ -> nil
    end
  end

  defp pick_from_header(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first()
    |> parse_accept_language()
  end

  defp parse_accept_language(nil), do: nil

  defp parse_accept_language(header) do
    header
    |> String.split(",")
    |> Enum.map(&(&1 |> String.split(";") |> List.first() |> String.trim() |> String.downcase()))
    |> Enum.map(&String.slice(&1, 0, 2))
    |> Enum.find(&(&1 in @supported))
  end
end
