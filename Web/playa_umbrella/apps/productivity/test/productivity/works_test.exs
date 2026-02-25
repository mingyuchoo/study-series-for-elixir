defmodule Productivity.WorksTest do
  use Productivity.DataCase

  alias Productivity.Works

  import Productivity.WorksFixtures

  describe "Lists" do
    test "list_lists/0 returns all lists" do
      list1 = list_fixture()
      list2 = list_fixture()

      lists = Works.list_lists()
      list_ids = Enum.map(lists, & &1.id)

      assert list1.id in list_ids
      assert list2.id in list_ids

      # Verify associations are preloaded
      first_list = List.first(lists)
      assert Ecto.assoc_loaded?(first_list.user)
      assert Ecto.assoc_loaded?(first_list.items)
    end

    test "get_list!/1 returns the list with given id" do
      list = list_fixture()
      fetched_list = Works.get_list!(list.id)

      assert fetched_list.id == list.id
      assert fetched_list.title == list.title
      assert Ecto.assoc_loaded?(fetched_list.user)
      assert Ecto.assoc_loaded?(fetched_list.items)
    end

    test "get_list!/1 raises error when list does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Works.get_list!(-1)
      end
    end

    test "create_list/1 with valid data creates a list" do
      attrs = valid_list_attributes()

      assert {:ok, list} = Works.create_list(attrs)
      assert list.title == attrs.title
      assert list.user_id == attrs.user_id
      assert list.item_count == 0
      assert Ecto.assoc_loaded?(list.user)
      assert Ecto.assoc_loaded?(list.items)
    end

    test "create_list/1 with invalid data returns error changeset" do
      assert {:error, changeset} = Works.create_list(%{})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "create_list/0 with no args returns error changeset" do
      assert {:error, changeset} = Works.create_list()
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "update_list/2 with valid data updates the list" do
      list = list_fixture()
      update_attrs = %{title: "Updated Title"}

      assert {:ok, updated_list} = Works.update_list(list, update_attrs)
      assert updated_list.title == "Updated Title"
    end

    test "update_list/2 with invalid data returns error changeset" do
      list = list_fixture()
      assert {:error, changeset} = Works.update_list(list, %{title: nil})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "delete_list/1 deletes the list" do
      list = list_fixture()
      assert {:ok, _deleted_list} = Works.delete_list(list)
      assert_raise Ecto.NoResultsError, fn -> Works.get_list!(list.id) end
    end

    test "increase_item_count/1 increments the item count" do
      list = list_fixture()
      assert list.item_count == 0

      assert {:ok, updated_list} = Works.increase_item_count(list)
      assert updated_list.item_count == 1

      assert {:ok, updated_list} = Works.increase_item_count(updated_list)
      assert updated_list.item_count == 2
    end

    test "decrease_item_count/1 decrements the item count" do
      list = list_fixture()
      {:ok, list} = Works.increase_item_count(list)
      {:ok, list} = Works.increase_item_count(list)
      assert list.item_count == 2

      assert {:ok, updated_list} = Works.decrease_item_count(list)
      assert updated_list.item_count == 1

      assert {:ok, updated_list} = Works.decrease_item_count(updated_list)
      assert updated_list.item_count == 0
    end

    test "decrease_item_count/1 does not go below zero" do
      list = list_fixture()
      assert list.item_count == 0

      assert {:ok, updated_list} = Works.decrease_item_count(list)
      assert updated_list.item_count == 0
    end

    test "change_list/1 returns a changeset" do
      list = list_fixture()
      changeset = Works.change_list(list)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data.id == list.id
      assert Ecto.assoc_loaded?(changeset.data.user)
      assert Ecto.assoc_loaded?(changeset.data.items)
    end

    test "change_list/2 returns a changeset with changes" do
      list = list_fixture()
      changeset = Works.change_list(list, %{title: "New Title"})

      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.title == "New Title"
    end
  end

  describe "Items" do
    test "list_items/0 returns all items" do
      list = list_fixture()
      item1 = item_fixture(list.id)
      item2 = item_fixture(list.id)

      items = Works.list_items()
      item_ids = Enum.map(items, & &1.id)

      assert item1.id in item_ids
      assert item2.id in item_ids

      # Verify associations are preloaded
      first_item = List.first(items)
      assert Ecto.assoc_loaded?(first_item.user)
      assert Ecto.assoc_loaded?(first_item.list)
    end

    test "get_item!/1 returns the item with given id" do
      list = list_fixture()
      item = item_fixture(list.id)
      fetched_item = Works.get_item!(item.id)

      assert fetched_item.id == item.id
      assert fetched_item.title == item.title
      assert Ecto.assoc_loaded?(fetched_item.user)
      assert Ecto.assoc_loaded?(fetched_item.list)
    end

    test "get_item!/1 raises error when item does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Works.get_item!(-1)
      end
    end

    test "create_item/1 with valid data creates an item" do
      list = list_fixture()
      attrs = valid_item_attributes(list.id)

      assert {:ok, item} = Works.create_item(attrs)
      assert item.title == attrs.title
      assert item.description == attrs.description
      assert item.status == :todo
      assert item.list_id == list.id
      assert Ecto.assoc_loaded?(item.user)
      assert Ecto.assoc_loaded?(item.list)
    end

    test "create_item/1 with invalid data returns error changeset" do
      assert {:error, changeset} = Works.create_item(%{})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "create_item/0 with no args returns error changeset" do
      assert {:error, changeset} = Works.create_item()
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "update_item/2 with valid data updates the item" do
      list = list_fixture()
      item = item_fixture(list.id)
      update_attrs = %{title: "Updated Item", status: :done}

      assert {:ok, updated_item} = Works.update_item(item, update_attrs)
      assert updated_item.title == "Updated Item"
      assert updated_item.status == :done
    end

    test "update_item/2 with invalid status returns error" do
      list = list_fixture()
      item = item_fixture(list.id)

      assert {:error, changeset} = Works.update_item(item, %{status: :invalid_status})
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "delete_item/1 deletes the item" do
      list = list_fixture()
      item = item_fixture(list.id)

      assert {:ok, _deleted_item} = Works.delete_item(item)
      assert_raise Ecto.NoResultsError, fn -> Works.get_item!(item.id) end
    end

    test "list_items_by_list_id/1 returns items for specific list" do
      list1 = list_fixture()
      list2 = list_fixture()
      item1 = item_fixture(list1.id)
      item2 = item_fixture(list1.id)
      _item3 = item_fixture(list2.id)

      items = Works.list_items_by_list_id(list1.id)
      item_ids = Enum.map(items, & &1.id)

      assert length(items) == 2
      assert item1.id in item_ids
      assert item2.id in item_ids
    end

    test "change_item/1 returns a changeset" do
      list = list_fixture()
      item = item_fixture(list.id)
      changeset = Works.change_item(item)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data.id == item.id
    end

    test "change_item/2 returns a changeset with changes" do
      list = list_fixture()
      item = item_fixture(list.id)
      changeset = Works.change_item(item, %{title: "Changed Title"})

      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.title == "Changed Title"
    end

    test "Item.status_values/0 returns all valid status values" do
      alias Productivity.Works.Item

      status_values = Item.status_values()

      assert status_values == [:todo, :doing, :done]
      assert :todo in status_values
      assert :doing in status_values
      assert :done in status_values
    end
  end
end
