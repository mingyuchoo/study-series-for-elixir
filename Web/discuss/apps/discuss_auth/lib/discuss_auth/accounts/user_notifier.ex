defmodule DiscussAuth.Accounts.UserNotifier do
  import Swoosh.Email

  alias Discuss.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Discuss", "noreply@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  회원가입 확인 이메일.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "이메일 인증 안내", """
    안녕하세요, #{user.email}님,

    아래 링크를 클릭하여 계정을 인증해주세요:

    #{url}

    이 요청을 하지 않으셨다면 이 이메일을 무시해주세요.
    """)
  end

  @doc """
  비밀번호 재설정 이메일.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "비밀번호 재설정", """
    안녕하세요, #{user.email}님,

    아래 링크를 클릭하여 비밀번호를 재설정해주세요:

    #{url}

    이 요청을 하지 않으셨다면 이 이메일을 무시해주세요.
    """)
  end
end
