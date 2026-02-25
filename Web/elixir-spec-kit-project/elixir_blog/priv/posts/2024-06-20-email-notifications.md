---
title: "이메일 및 알림 시스템"
author: "임동현"
tags: ["notifications", "email", "devops"]
thumbnail: "/images/thumbnails/email-notifications.jpg"
summary: "Swoosh를 이용한 이메일 발송 및 다양한 알림 시스템을 구축합니다."
published_at: 2024-06-20T14:00:00Z
is_popular: false
---

효과적한 알림 시스템은 사용자 참여도를 높입니다. 이메일 및 알림 시스템을 구현해봅시다.

## Swoosh 이메일 설정

```elixir
# config/config.exs
config :myapp, Myapp.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: System.get_env("SMTP_RELAY"),
  username: System.get_env("SMTP_USERNAME"),
  password: System.get_env("SMTP_PASSWORD"),
  port: String.to_integer(System.get_env("SMTP_PORT", "587")),
  tls: :always,
  auth: :cram_md5

# 또는 SendGrid 사용
config :myapp, Myapp.Mailer,
  adapter: Swoosh.Adapters.Sendgrid,
  api_key: System.get_env("SENDGRID_API_KEY")
```

## 이메일 템플릿

```elixir
# lib/myapp/emails/user_emails.ex
defmodule Myapp.Emails.UserEmails do
  import Swoosh.Email

  def welcome_email(user) do
    new()
    |> to({user.name, user.email})
    |> from({"MyApp", "noreply@myapp.com"})
    |> subject("환영합니다, #{user.name}님!")
    |> html_body(welcome_html(user))
    |> text_body(welcome_text(user))
  end

  def password_reset_email(user, reset_token) do
    reset_url = "https://myapp.com/reset?token=#{reset_token}"

    new()
    |> to({user.name, user.email})
    |> from({"MyApp", "noreply@myapp.com"})
    |> subject("비밀번호 재설정")
    |> html_body("""
      <h1>비밀번호 재설정</h1>
      <p>아래 링크를 클릭하여 비밀번호를 재설정하세요.</p>
      <a href="#{reset_url}">비밀번호 재설정</a>
      <p>1시간 내에 재설정하세요.</p>
    """)
  end

  def notification_email(user, title, message) do
    new()
    |> to({user.name, user.email})
    |> from({"MyApp", "noreply@myapp.com"})
    |> subject(title)
    |> html_body(notification_html(title, message))
  end

  defp welcome_html(user) do
    """
    <html>
      <body>
        <h1>환영합니다, #{user.name}님!</h1>
        <p>MyApp에 가입하셨습니다.</p>
        <p><a href="https://myapp.com">앱으로 이동</a></p>
      </body>
    </html>
    """
  end

  defp welcome_text(user) do
    """
    환영합니다, #{user.name}님!

    MyApp에 가입하셨습니다.
    https://myapp.com 에서 시작하세요.
    """
  end

  defp notification_html(title, message) do
    """
    <html>
      <body>
        <h1>#{title}</h1>
        <p>#{message}</p>
      </body>
    </html>
    """
  end
end
```

## 비동기 이메일 발송

```elixir
# lib/myapp/workers/email_worker.ex
defmodule Myapp.Workers.EmailWorker do
  use Oban.Worker, queue: :emails, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "welcome", "user_id" => user_id}}) do
    user = Repo.get!(User, user_id)

    user
    |> Myapp.Emails.UserEmails.welcome_email()
    |> Myapp.Mailer.deliver()

    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "password_reset", "user_id" => user_id, "token" => token}}) do
    user = Repo.get!(User, user_id)

    user
    |> Myapp.Emails.UserEmails.password_reset_email(token)
    |> Myapp.Mailer.deliver()

    :ok
  end
end

# 사용
%{"type" => "welcome", "user_id" => user.id}
|> Myapp.Workers.EmailWorker.new()
|> Oban.insert()
```

## 푸시 알림

```elixir
# lib/myapp/notifications/push_notification.ex
defmodule Myapp.Notifications.PushNotification do
  def send_notification(user, title, message) do
    user
    |> get_push_tokens()
    |> Enum.each(fn token ->
      send_push(token, title, message)
    end)
  end

  defp get_push_tokens(user) do
    Repo.all(from(d in Device, where: d.user_id == ^user.id, select: d.push_token))
  end

  defp send_push(token, title, message) do
    payload = %{
      notification: %{
        title: title,
        body: message
      }
    }

    case Pigeon.FCM.send(Pigeon.FCM.Notification.new(token, payload)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## SMS 알림

```elixir
# lib/myapp/notifications/sms_notification.ex
defmodule Myapp.Notifications.SmsNotification do
  def send_sms(phone_number, message) do
    client = ExTwilio.client()

    ExTwilio.Message.create(
      client,
      to: phone_number,
      from: System.get_env("TWILIO_PHONE_NUMBER"),
      body: message
    )
  end
end
```

## 알림 기록

```elixir
# lib/myapp/notifications/notification.ex
defmodule Myapp.Notifications.Notification do
  use Ecto.Schema

  schema "notifications" do
    field :user_id, :id
    field :type, :string  # email, sms, push
    field :title, :string
    field :message, :string
    field :status, :string  # pending, sent, failed
    field :metadata, :map

    timestamps()
  end

  def changeset(notification, attrs) do
    notification
    |> Ecto.Changeset.cast(attrs, [:user_id, :type, :title, :message, :status, :metadata])
    |> Ecto.Changeset.validate_required([:user_id, :type, :message])
  end
end

# 알림 로깅
def log_notification(user_id, type, message) do
  %Notification{}
  |> Notification.changeset(%{
    user_id: user_id,
    type: type,
    message: message,
    status: "pending"
  })
  |> Repo.insert()
end
```

## 알림 설정

```elixir
# lib/myapp/user_preferences.ex
defmodule Myapp.UserPreferences do
  schema "user_preferences" do
    field :user_id, :id
    field :email_notifications, :boolean, default: true
    field :push_notifications, :boolean, default: true
    field :sms_notifications, :boolean, default: false
    field :email_frequency, :string  # immediate, daily, weekly

    timestamps()
  end

  def should_send_email?(user) do
    preferences = Repo.get_by(__MODULE__, user_id: user.id)
    preferences && preferences.email_notifications
  end

  def should_send_push?(user) do
    preferences = Repo.get_by(__MODULE__, user_id: user.id)
    preferences && preferences.push_notifications
  end
end
```

## 결론

다양한 알림 채널을 통한 효과적한 사용자 소통은 애플리케이션의 성공을 결정합니다. 이메일, 푸시, SMS 등 여러 채널을 조합하여 사용자 선호도에 맞게 알림을 제공할 수 있습니다.