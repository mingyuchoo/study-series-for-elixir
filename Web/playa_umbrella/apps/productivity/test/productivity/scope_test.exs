defmodule Productivity.ScopeTest do
  use Productivity.DataCase

  alias Productivity.Scope
  import Playa.AccountsFixtures

  describe "for_user/1" do
    test "creates a scope with nil user" do
      scope = Scope.for_user(nil)

      assert %Scope{} = scope
      assert scope.current_user == nil
      assert scope.current_user_id == nil
    end

    test "creates a scope with a user" do
      user = user_fixture()
      scope = Scope.for_user(user)

      assert %Scope{} = scope
      assert scope.current_user == user
      assert scope.current_user_id == user.id
    end
  end
end
