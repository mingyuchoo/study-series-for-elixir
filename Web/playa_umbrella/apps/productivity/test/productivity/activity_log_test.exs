defmodule Productivity.ActivityLogTest do
  use Productivity.DataCase

  alias Productivity.ActivityLog
  alias Productivity.ActivityLog.Entry
  alias Productivity.Scope
  alias Productivity.Repo

  import Productivity.WorksFixtures
  import Productivity.AccountFixtures

  setup do
    user = user_fixture()
    %{user: user, scope: Scope.for_user(user)}
  end

  describe "log/3 with List" do
    test "creates an entry for a list with valid attributes", %{user: user, scope: scope} do
      # Create a list with the same user as the scope
      list = list_fixture(%{user_id: user.id})

      entry = ActivityLog.log(scope, list, %{action: "created"})

      assert %Entry{} = entry
      assert entry.action == "created"
      assert entry.user_id == user.id
      assert entry.list_id == list.id
      assert entry.item_id == nil
    end

    test "creates an entry for a deleted list (state: :deleted)", %{user: user, scope: scope} do
      # Create a list with the same user as the scope
      list = list_fixture(%{user_id: user.id})

      # Delete the list to get a deleted struct
      {:ok, deleted_list} = Repo.delete(list)

      entry = ActivityLog.log(scope, deleted_list, %{action: "deleted"})

      assert %Entry{} = entry
      assert entry.action == "deleted"
      assert entry.user_id == user.id
      assert entry.list_id == nil
      assert entry.item_id == nil
    end
  end

  describe "log/3 with Item" do
    test "creates an entry for an item with valid attributes", %{user: user, scope: scope} do
      # Create a list with the same user as the scope
      list = list_fixture(%{user_id: user.id})
      item = item_fixture(list.id, %{user_id: user.id})

      entry = ActivityLog.log(scope, item, %{action: "created"})

      assert %Entry{} = entry
      assert entry.action == "created"
      assert entry.user_id == user.id
      assert entry.list_id == list.id
      assert entry.item_id == item.id
    end

    test "creates an entry for a deleted item (state: :deleted)", %{user: user, scope: scope} do
      # Create a list with the same user as the scope
      list = list_fixture(%{user_id: user.id})
      item = item_fixture(list.id, %{user_id: user.id})

      # Delete the item to get a deleted struct
      {:ok, deleted_item} = Repo.delete(item)

      entry = ActivityLog.log(scope, deleted_item, %{action: "deleted"})

      assert %Entry{} = entry
      assert entry.action == "deleted"
      assert entry.user_id == user.id
      assert entry.list_id == list.id
      assert entry.item_id == nil
    end
  end

  describe "Entry.changeset/2" do
    test "valid changeset with required fields" do
      changeset =
        %Entry{}
        |> Entry.changeset(%{action: "created"})

      assert changeset.valid?
      assert changeset.changes.action == "created"
    end

    test "invalid changeset without action" do
      changeset =
        %Entry{}
        |> Entry.changeset(%{})

      refute changeset.valid?
      assert %{action: ["can't be blank"]} = errors_on(changeset)
    end

    test "changeset ignores unknown fields" do
      changeset =
        %Entry{}
        |> Entry.changeset(%{action: "updated", unknown_field: "value"})

      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :unknown_field)
    end
  end
end
