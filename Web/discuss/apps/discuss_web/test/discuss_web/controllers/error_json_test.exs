defmodule DiscussWeb.ErrorJSONTest do
  use DiscussWeb.ConnCase, async: true

  test "404 에러를 JSON으로 렌더링한다" do
    assert DiscussWeb.ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Not Found"}
           }
  end

  test "500 에러를 JSON으로 렌더링한다" do
    assert DiscussWeb.ErrorJSON.render("500.json", %{}) == %{
             errors: %{detail: "Internal Server Error"}
           }
  end
end
