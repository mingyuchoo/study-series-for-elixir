defmodule WebWeb do
  @moduledoc """
  컨트롤러, 컴포넌트, 채널 등 웹 인터페이스를 정의하기 위한
  진입점 모듈입니다.

  애플리케이션에서 다음과 같이 사용할 수 있습니다:

      use WebWeb, :controller
      use WebWeb, :html

  아래 정의들은 모든 컨트롤러, 컴포넌트 등에서 실행되므로,
  imports, uses, aliases에만 집중하여 짧고 깔끔하게 유지하세요.

  아래 quoted 표현식 내에 함수를 정의하지 마세요.
  대신 추가 모듈을 정의하고 여기서 import 하세요.
  """

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # 파이프라인에서 사용할 공통 연결 및 컨트롤러 함수 import
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # 컨트롤러에서 편의 함수 import
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # HTML 렌더링을 위한 일반 헬퍼 포함
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML 이스케이프 기능
      import Phoenix.HTML
      # 핵심 UI 컴포넌트
      import WebWeb.CoreComponents

      # 템플릿에서 사용하는 공통 모듈
      alias Phoenix.LiveView.JS
      alias WebWeb.Layouts

      # ~p 시길을 사용한 라우트 생성
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: WebWeb.Endpoint,
        router: WebWeb.Router,
        statics: WebWeb.static_paths()
    end
  end

  @doc """
  사용될 때 적절한 controller/live_view/etc로 디스패치합니다.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
