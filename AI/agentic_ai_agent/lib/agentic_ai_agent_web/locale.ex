defmodule AgenticAiAgentWeb.Locale do
  @moduledoc """
  Single source of truth for the supported UI locales and the LiveView
  `on_mount/4` hook that activates them.
  """

  @supported ~w(en ko)
  @default "en"

  def supported, do: @supported
  def default, do: @default

  def labels do
    %{
      "en" => "EN",
      "ko" => "KO"
    }
  end

  @doc """
  LiveView `on_mount` callback. Wire it up in the `live_session`:

      live_session :default, on_mount: AgenticAiAgentWeb.Locale do
        live "/...", ...
      end
  """
  def on_mount(:default, _params, session, socket) do
    locale =
      case socket.assigns[:current_user] do
        %{preferred_locale: l} when l in @supported -> l
        _ -> nil
      end ||
        case session["locale"] do
          l when l in @supported -> l
          _ -> @default
        end

    Gettext.put_locale(AgenticAiAgentWeb.Gettext, locale)

    socket =
      socket
      |> Phoenix.Component.assign(:locale, locale)
      |> Phoenix.Component.assign_new(:current_path, fn -> "/" end)
      |> Phoenix.LiveView.attach_hook(:track_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)

        path =
          (uri.path || "/") <>
            if(uri.query in [nil, ""], do: "", else: "?" <> uri.query)

        {:cont, Phoenix.Component.assign(socket, :current_path, path)}
      end)

    {:cont, socket}
  end
end
