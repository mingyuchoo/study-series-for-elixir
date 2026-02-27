defmodule DiscussAuth.Accounts.UserNotifierTest do
  use Discuss.DataCase

  alias DiscussAuth.Accounts.UserNotifier

  import DiscussAuth.AccountsFixtures

  describe "deliver_confirmation_instructions/2" do
    test "이메일 인증 안내 이메일을 발송한다" do
      user = user_fixture()
      assert {:ok, email} = UserNotifier.deliver_confirmation_instructions(user, "http://example.com/confirm")
      assert email.to == [{nil, user.email}] || email.to == [{"", user.email}] || email.to == user.email
      assert email.subject == "이메일 인증 안내"
    end
  end

  describe "deliver_reset_password_instructions/2" do
    test "비밀번호 재설정 이메일을 발송한다" do
      user = user_fixture()
      assert {:ok, email} = UserNotifier.deliver_reset_password_instructions(user, "http://example.com/reset")
      assert email.subject == "비밀번호 재설정"
    end
  end
end
