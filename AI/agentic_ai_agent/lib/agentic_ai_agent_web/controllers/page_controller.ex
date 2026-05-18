defmodule AgenticAiAgentWeb.PageController do
  use AgenticAiAgentWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
