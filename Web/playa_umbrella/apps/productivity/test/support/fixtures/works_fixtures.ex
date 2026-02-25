defmodule Productivity.WorksFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Productivity.Works` context.
  """

  alias Productivity.Works
  import Playa.AccountsFixtures

  def unique_list_title, do: "List#{System.unique_integer()}"

  def valid_list_attributes(attrs \\ %{}) do
    # Create a test user using Playa fixtures to ensure proper setup
    user = user_fixture()

    Enum.into(attrs, %{
      title: unique_list_title(),
      user_id: user.id,
      item_count: 0
    })
  end

  def list_fixture(attrs \\ %{}) do
    {:ok, list} =
      attrs
      |> valid_list_attributes()
      |> Works.create_list()

    list
  end

  def unique_item_title, do: "Item#{System.unique_integer()}"

  def valid_item_attributes(list_id, attrs \\ %{}) do
    # Create a test user using Playa fixtures to ensure proper setup
    user = user_fixture()

    Enum.into(attrs, %{
      title: unique_item_title(),
      description: "Test item description",
      status: :todo,
      user_id: user.id,
      list_id: list_id
    })
  end

  def item_fixture(list_id, attrs \\ %{}) do
    {:ok, item} =
      list_id
      |> valid_item_attributes(attrs)
      |> Works.create_item()

    item
  end
end
