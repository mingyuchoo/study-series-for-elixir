defmodule DiscussWeb.ErrorHTMLTest do
  use DiscussWeb.ConnCase, async: true

  test "404 페이지를 렌더링한다" do
    assert DiscussWeb.ErrorHTML.render("404.html", %{}) == "Not Found"
  end

  test "500 페이지를 렌더링한다" do
    assert DiscussWeb.ErrorHTML.render("500.html", %{}) == "Internal Server Error"
  end
end
