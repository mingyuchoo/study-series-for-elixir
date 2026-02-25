---
title: "다국어 지원 및 로컬라이제이션"
author: "김철수"
tags: ["localization", "web-dev", "programming"]
thumbnail: "/images/thumbnails/localization.jpg"
summary: "Gettext를 이용한 다국어 지원 및 지역화를 배웁니다."
published_at: 2024-07-05T11:20:00Z
is_popular: true
---

글로벌 애플리케이션을 만들려면 다국어 지원이 필수입니다. Phoenix Gettext를 이용한 로컬라이제이션을 알아봅시다.

## Gettext 설정

```elixir
# mix.exs
defp deps do
  [
    {:gettext, "~> 0.20"}
  ]
end

# config/config.exs
config :myapp, MyappWeb.Gettext,
  default_locale: "en",
  locales: ["en", "ko", "ja", "zh"]
```

## 메시지 작성

```elixir
# lib/myapp_web/gettext.ex
defmodule MyappWeb.Gettext do
  use Gettext, otp_app: :myapp
end

# 컨트롤러에서 사용
defmodule MyappWeb.PageController do
  use MyappWeb, :controller

  def index(conn, _params) do
    message = gettext("Welcome to MyApp")
    render(conn, "index.html", message: message)
  end
end

# 템플릿에서 사용
<h1><%= gettext("Welcome") %></h1>
<p><%= dgettext("greetings", "Hello, %{name}!", name: "John") %></p>
```

## 번역 파일 생성

```bash
# 번역 파일 추출
mix gettext.extract

# 새 언어 추가
mix gettext.merge priv/gettext
```

```po
# priv/gettext/en/LC_MESSAGES/default.po
msgid ""
msgstr ""
"Language: en\n"
"Plural-Forms: nplurals=2\n"

msgid "Welcome"
msgstr "Welcome"

msgid "Hello, %{name}!"
msgstr "Hello, %{name}!"

# priv/gettext/ko/LC_MESSAGES/default.po
msgid ""
msgstr ""
"Language: ko\n"
"Plural-Forms: nplurals=1\n"

msgid "Welcome"
msgstr "환영합니다"

msgid "Hello, %{name}!"
msgstr "안녕하세요, %{name}님!"
```

## 언어 선택

```elixir
# lib/myapp_web/plugs/set_locale.ex
defmodule MyappWeb.Plugs.SetLocale do
  import Plug.Conn

  def init(_options) do
    []
  end

  def call(conn, _options) do
    locale = determine_locale(conn)
    Gettext.put_locale(MyappWeb.Gettext, locale)
    assign(conn, :locale, locale)
  end

  defp determine_locale(conn) do
    # 순서: URL 파라미터 > 쿠키 > Accept-Language > 기본값
    conn.params["locale"] ||
      get_session(conn, :locale) ||
      get_locale_from_accept_language(conn) ||
      "en"
  end

  defp get_locale_from_accept_language(conn) do
    case get_req_header(conn, "accept-language") do
      [header | _] ->
        header
        |> String.split(",")
        |> List.first("")
        |> String.split(";")
        |> List.first("")
        |> String.downcase()
      [] -> nil
    end
  end
end
```

## 복수형 처리

```elixir
# 컨트롤러
def show_items(conn, _params) do
  count = 5

  message = ngettext(
    "You have %{count} item",
    "You have %{count} items",
    count,
    count: count
  )

  render(conn, "show.html", message: message)
end
```

## 날짜 및 시간 지역화

```elixir
defmodule LocalizationHelper do
  def format_date(date, locale) do
    case locale do
      "ko" -> Timex.format!(date, "%Y년 %m월 %d일", :strftime)
      "en" -> Timex.format!(date, "%B %d, %Y", :strftime)
      "ja" -> Timex.format!(date, "%Y年%m月%d日", :strftime)
      _ -> Timex.format!(date, "%Y-%m-%d", :strftime)
    end
  end

  def format_currency(amount, locale) do
    case locale do
      "ko" -> "₩#{Number.Currency.number_to_currency(amount)}"
      "en" -> "$#{Number.Currency.number_to_currency(amount)}"
      "ja" -> "¥#{Number.Currency.number_to_currency(amount)}"
      _ -> "#{Number.Currency.number_to_currency(amount)}"
    end
  end
end
```

## LiveView에서의 지역화

```elixir
defmodule MyappWeb.PostsLive.Index do
  use MyappWeb, :live_view

  def mount(_params, _session, socket) do
    locale = get_locale(socket)
    {:ok, assign(socket, locale: locale)}
  end

  def render(assigns) do
    ~H"""
    <h1><%= gettext("Posts") %></h1>
    <table>
      <thead>
        <tr>
          <th><%= gettext("Title") %></th>
          <th><%= gettext("Created At") %></th>
          <th><%= gettext("Author") %></th>
        </tr>
      </thead>
      <tbody>
        <%= for post <- @posts do %>
          <tr>
            <td><%= post.title %></td>
            <td><%= format_date(post.created_at, @locale) %></td>
            <td><%= post.author.name %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  defp format_date(date, locale) do
    LocalizationHelper.format_date(date, locale)
  end

  defp get_locale(socket) do
    Map.get(socket.assigns, :locale, "en")
  end
end
```

## 결론

다국어 지원은 애플리케이션의 글로벌 확장을 가능하게 합니다. Gettext를 활용하면 효율적으로 번역을 관리하고 다양한 지역의 사용자에게 최적화된 경험을 제공할 수 있습니다.