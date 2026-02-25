// Phoenix 채널을 사용하려면 `mix help phx.gen.channel`을 실행하여
// 시작하고 아래 줄의 주석을 해제하세요.
// import "./user_socket.js"

// 의존성을 포함하는 두 가지 방법이 있습니다.
//
// 가장 간단한 옵션은 assets/vendor에 넣고
// 상대 경로를 사용하여 import하는 것입니다:
//
//     import "../vendor/some-package.js"
//
// 또는 `npm install some-package --prefix assets`로 설치하고
// 패키지 이름으로 시작하는 경로로 import할 수 있습니다:
//
//     import "some-package"
//
// CSS를 import하려는 의존성이 있으면 esbuild가 별도의 `app.css` 파일을 생성합니다.
// 로드하려면 `root.html.heex` 파일에 두 번째 `<link>`를 추가하면 됩니다.

// 폼과 버튼에서 method=PUT/DELETE를 처리하기 위해 phoenix_html 포함
import "phoenix_html"
// Phoenix Socket 및 LiveView 설정 수립
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
})

// 라이브 네비게이션 및 폼 제출 시 프로그레스 바 표시
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// 페이지에 LiveView가 있으면 연결
liveSocket.connect()

// 웹 콘솔 디버그 로그 및 지연 시뮬레이션을 위해 window에 liveSocket 노출:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // 브라우저 세션 동안 활성화
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// 아래 줄들은 phoenix_live_reload 개발 편의 기능을 활성화합니다:
//
//     1. 서버 로그를 브라우저 콘솔로 스트리밍
//     2. 요소를 클릭하여 코드 에디터에서 정의로 이동
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // 서버 로그 스트리밍을 클라이언트로 활성화.
    // reloader.disableServerLogs()로 비활성화
    reloader.enableServerLogs()

    // 클릭한 요소의 HEEx 컴포넌트 file:line에서 설정된 PLUG_EDITOR 열기
    //
    //   * "c" 키를 누른 상태로 클릭하면 호출자 위치에서 열기
    //   * "d" 키를 누른 상태로 클릭하면 함수 컴포넌트 정의 위치에서 열기
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

