# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Productivity.Repo.insert!(%Productivity.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Productivity.Works
alias Productivity.Works.List
alias Productivity.Repo

[
  %{title: "Home", user_id: 1},
  %{title: "Office", user_id: 1},
  %{title: "Community", user_id: 1}
]
|> Enum.each(fn attr ->
  case Repo.get_by(List, title: attr.title, user_id: attr.user_id) do
    nil ->
      case Works.create_list(attr) do
        {:ok, _list} -> :ok
        {:error, changeset} -> raise "Failed to create list: #{inspect(changeset)}"
      end

    _list ->
      :ok
  end
end)

# Get list IDs by title
home_list = Repo.get_by(List, title: "Home", user_id: 1)
office_list = Repo.get_by(List, title: "Office", user_id: 1)
community_list = Repo.get_by(List, title: "Community", user_id: 1)

[
  %{title: "Do laundry", description: "Given, When, Then", user_id: 1, list_id: home_list.id},
  %{
    title: "Do refactoring code",
    description: "Given, When, Then",
    user_id: 1,
    list_id: office_list.id
  },
  %{
    title: "Check post and add comments",
    description: "Given, When, Then",
    user_id: 1,
    list_id: community_list.id
  }
]
|> Enum.each(fn attr ->
  case Repo.get_by(Productivity.Works.Item, title: attr.title, list_id: attr.list_id) do
    nil ->
      case Works.create_item(attr) do
        {:ok, item} ->
          Works.increase_item_count(item.list)

        {:error, changeset} ->
          raise "Failed to create item: #{inspect(changeset)}"
      end

    _item ->
      :ok
  end
end)
