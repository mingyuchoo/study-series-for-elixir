defmodule WebWeb.ErrorHTMLTest do
  use WebWeb.ConnCase, async: true

  # 커스텀 뷰 테스트를 위해 render_to_string/4 가져오기
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    assert render_to_string(WebWeb.ErrorHTML, "404", "html", []) == "Not Found"
  end

  test "renders 500.html" do
    assert render_to_string(WebWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end
end
