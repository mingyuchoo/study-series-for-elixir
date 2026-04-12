이것은 Phoenix 웹 프레임워크를 사용하여 작성된 웹 애플리케이션입니다.

## 프로젝트 가이드라인

- 모든 변경사항을 완료한 후 `mix precommit` 별칭을 사용하여 미해결 문제를 수정하세요
- HTTP 요청에는 이미 포함되어 있고 사용 가능한 `:req` (`Req`) 라이브러리를 사용하고, `:httpoison`, `:tesla`, `:httpc`는 **피하세요**. Req는 기본적으로 포함되어 있으며 Phoenix 앱에서 선호되는 HTTP 클라이언트입니다

### Phoenix v1.8 가이드라인

- **항상** LiveView 템플릿을 `<Layouts.app flash={@flash} ...>`로 시작하여 모든 내부 콘텐츠를 감싸세요
- `MyAppWeb.Layouts` 모듈은 `my_app_web.ex` 파일에서 별칭이 지정되어 있으므로 다시 별칭을 지정할 필요 없이 사용할 수 있습니다
- `current_scope` 할당이 없다는 오류가 발생할 때마다:
  - 인증된 라우트 가이드라인을 따르지 않았거나 `current_scope`를 `<Layouts.app>`에 전달하지 않았습니다
  - **항상** 라우트를 적절한 `live_session`으로 이동하고 필요에 따라 `current_scope`를 전달하여 `current_scope` 오류를 수정하세요
- Phoenix v1.8은 `<.flash_group>` 컴포넌트를 `Layouts` 모듈로 이동했습니다. `layouts.ex` 모듈 외부에서 `<.flash_group>`을 호출하는 것은 **금지**됩니다
- 기본적으로 `core_components.ex`는 히어로 아이콘용 `<.icon name="hero-x-mark" class="w-5 h-5"/>` 컴포넌트를 가져옵니다. 아이콘에는 **항상** `<.icon>` 컴포넌트를 사용하고, `Heroicons` 모듈이나 유사한 것은 **절대** 사용하지 마세요
- 사용 가능한 경우 `core_components.ex`의 폼 입력에는 **항상** 가져온 `<.input>` 컴포넌트를 사용하세요. `<.input>`이 가져와져 있으며 이를 사용하면 단계를 절약하고 오류를 방지할 수 있습니다
- 기본 입력 클래스를 재정의하는 경우 (`<.input class="myclass px-2 py-1 rounded-lg">`) 자체 값으로 클래스를 지정하면 기본 클래스가 상속되지 않으므로 사용자 정의 클래스가 입력을 완전히 스타일링해야 합니다

### JS 및 CSS 가이드라인

- **Tailwind CSS 클래스와 사용자 정의 CSS 규칙을 사용**하여 세련되고 반응형이며 시각적으로 멋진 인터페이스를 만드세요.
- Tailwindcss v4는 **더 이상 tailwind.config.js가 필요하지 않으며** `app.css`에서 새로운 import 구문을 사용합니다:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- `phx.new`로 생성된 프로젝트의 app.css 파일에서 **항상 이 import 구문을 사용하고 유지하세요**
- 원시 css를 작성할 때 `@apply`를 **절대** 사용하지 마세요
- 독특하고 세계적 수준의 디자인을 위해 daisyUI를 사용하는 대신 **항상** 자체 tailwind 기반 컴포넌트를 수동으로 작성하세요
- 기본적으로 **app.js와 app.css 번들만 지원됩니다**
  - 레이아웃에서 외부 벤더 스크립트 `src`나 링크 `href`를 참조할 수 없습니다
  - 벤더 의존성을 app.js와 app.css로 가져와야 사용할 수 있습니다
  - **템플릿 내에서 인라인 <script>custom js</script> 태그를 절대 작성하지 마세요**

### UI/UX 및 디자인 가이드라인

- 사용성, 미학, 현대적 디자인 원칙에 중점을 둔 **세계적 수준의 UI 디자인을 제작**하세요
- **미묘한 마이크로 인터랙션**을 구현하세요 (예: 버튼 호버 효과, 부드러운 전환)
- 세련되고 프리미엄한 느낌을 위해 **깔끔한 타이포그래피, 간격, 레이아웃 균형**을 보장하세요
- 호버 효과, 로딩 상태, 부드러운 페이지 전환과 같은 **즐거운 세부사항**에 집중하세요


<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir 가이드라인

- Elixir 리스트는 **액세스 구문을 통한 인덱스 기반 액세스를 지원하지 않습니다**

  **절대 이렇게 하지 마세요 (유효하지 않음)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  대신, 인덱스 기반 리스트 액세스에는 **항상** `Enum.at`, 패턴 매칭, 또는 `List`를 사용하세요:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir 변수는 불변이지만 재바인딩될 수 있으므로, `if`, `case`, `cond` 등과 같은 블록 표현식의 경우
  사용하려면 표현식의 결과를 변수에 바인딩해야 하며 표현식 내부에서 결과를 재바인딩할 수 없습니다:

      # 유효하지 않음: `if` 내부에서 재바인딩하고 있으며 결과가 할당되지 않음
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # 유효함: `if`의 결과를 새 변수에 재바인딩
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- 순환 의존성과 컴파일 오류를 일으킬 수 있으므로 **절대** 같은 파일에 여러 모듈을 중첩하지 마세요
- 구조체는 기본적으로 Access 동작을 구현하지 않으므로 구조체에서 맵 액세스 구문(`changeset[:field]`)을 **절대** 사용하지 마세요. 일반 구조체의 경우 `my_struct.field`와 같이 필드에 직접 액세스하거나 구조체에서 사용 가능한 상위 수준 API(체인지셋의 경우 `Ecto.Changeset.get_field/2`)를 사용해야 합니다
- Elixir의 표준 라이브러리에는 날짜 및 시간 조작에 필요한 모든 것이 있습니다. 필요에 따라 문서에 액세스하여 일반적인 `Time`, `Date`, `DateTime`, `Calendar` 인터페이스에 익숙해지세요. 요청받거나 날짜/시간 파싱을 위한 경우(`date_time_parser` 패키지 사용 가능)가 아니면 **절대** 추가 의존성을 설치하지 마세요
- 사용자 입력에 `String.to_atom/1`을 사용하지 마세요 (메모리 누수 위험)
- 술어 함수 이름은 `is_`로 시작하지 않아야 하며 물음표로 끝나야 합니다. `is_thing`과 같은 이름은 가드용으로 예약되어야 합니다
- `DynamicSupervisor`와 `Registry`와 같은 Elixir의 내장 OTP 프리미티브는 자식 스펙에 이름이 필요합니다. 예: `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, 그런 다음 `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`를 사용할 수 있습니다
- 백프레셔가 있는 동시 열거에는 `Task.async_stream(collection, callback, options)`를 사용하세요. 대부분의 경우 옵션으로 `timeout: :infinity`를 전달하고 싶을 것입니다

## Mix 가이드라인

- 작업을 사용하기 전에 문서와 옵션을 읽으세요 (`mix help task_name` 사용)
- 테스트 실패를 디버그하려면 `mix test test/my_test.exs`로 특정 파일의 테스트를 실행하거나 `mix test --failed`로 이전에 실패한 모든 테스트를 실행하세요
- `mix deps.clean --all`은 **거의 필요하지 않습니다**. 충분한 이유가 없는 한 사용을 **피하세요**

## 테스트 가이드라인

- 테스트 간 정리를 보장하므로 테스트에서 프로세스를 시작할 때 **항상 `start_supervised!/1`을 사용하세요**
- 테스트에서 `Process.sleep/1`과 `Process.alive?/1`을 **피하세요**
  - 프로세스가 완료되기를 기다리기 위해 잠자기 대신, **항상** `Process.monitor/1`을 사용하고 DOWN 메시지를 어설트하세요:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - 다음 호출 전에 동기화하기 위해 잠자기 대신, **항상** `_ = :sys.get_state/1`을 사용하여 프로세스가 이전 메시지를 처리했는지 확인하세요
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix 가이드라인

- Phoenix 라우터 `scope` 블록에는 범위 내의 모든 라우트에 접두사가 붙는 선택적 별칭이 포함됩니다. 중복 모듈 접두사를 피하기 위해 범위 내에서 라우트를 생성할 때 **항상** 이를 염두에 두세요.

- 라우트 정의를 위해 자체 `alias`를 생성할 **필요가 없습니다**! `scope`가 별칭을 제공합니다:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  UserLive 라우트는 `AppWeb.Admin.UserLive` 모듈을 가리킵니다

- `Phoenix.View`는 더 이상 필요하지 않거나 Phoenix에 포함되지 않으므로 사용하지 마세요
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
## Ecto 가이드라인

- 템플릿에서 액세스될 때 쿼리에서 Ecto 연관관계를 **항상** 미리 로드하세요. 예: `message.user.email`을 참조해야 하는 메시지
- `seeds.exs`를 작성할 때 `import Ecto.Query` 및 기타 지원 모듈을 기억하세요
- `Ecto.Schema` 필드는 `:text` 컬럼의 경우에도 항상 `:string` 타입을 사용합니다. 예: `field :name, :string`
- `Ecto.Changeset.validate_number/2`는 **`:allow_nil` 옵션을 지원하지 않습니다**. 기본적으로 Ecto 검증은 주어진 필드에 대한 변경사항이 존재하고 변경 값이 nil이 아닌 경우에만 실행되므로 그러한 옵션은 절대 필요하지 않습니다
- 체인지셋 필드에 액세스하려면 `Ecto.Changeset.get_field(changeset, :field)`를 **반드시** 사용해야 합니다
- `user_id`와 같이 프로그래밍 방식으로 설정되는 필드는 보안상의 이유로 `cast` 호출이나 유사한 곳에 나열되어서는 안 됩니다. 대신 구조체를 생성할 때 명시적으로 설정되어야 합니다
- 마이그레이션 파일을 생성할 때 올바른 타임스탬프와 규칙이 적용되도록 **항상** `mix ecto.gen.migration migration_name_using_underscores`를 호출하세요
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->
## Phoenix HTML 가이드라인

- Phoenix 템플릿은 **항상** `~H` 또는 .html.heex 파일(HEEx로 알려짐)을 사용하며, **절대** `~E`를 사용하지 마세요
- 폼을 구축할 때 **항상** 가져온 `Phoenix.Component.form/1`과 `Phoenix.Component.inputs_for/1` 함수를 사용하세요. 구식인 `Phoenix.HTML.form_for`나 `Phoenix.HTML.inputs_for`는 **절대** 사용하지 마세요
- 폼을 구축할 때 **항상** 이미 가져온 `Phoenix.Component.to_form/2`를 사용하세요 (`assign(socket, form: to_form(...))`와 `<.form for={@form} id="msg-form">`), 그런 다음 템플릿에서 `@form[:field]`를 통해 해당 폼에 액세스하세요
- 템플릿을 작성할 때 주요 요소(폼, 버튼 등)에 **항상** 고유한 DOM ID를 추가하세요. 이러한 ID는 나중에 테스트에서 사용할 수 있습니다 (`<.form for={@form} id="product-form">`)
- "앱 전체" 템플릿 가져오기의 경우, `my_app_web.ex`의 `html_helpers` 블록으로 가져오기/별칭을 지정할 수 있으므로 모든 LiveView, LiveComponent 및 `use MyAppWeb, :html`을 수행하는 모든 모듈에서 사용할 수 있습니다 ("my_app"을 실제 앱 이름으로 바꾸세요)

- Elixir는 `if/else`를 지원하지만 **`if/else if` 또는 `if/elsif`를 지원하지 않습니다**. **Elixir에서 `else if` 또는 `elseif`를 절대 사용하지 마세요**, 여러 조건문에는 **항상** `cond` 또는 `case`를 사용하세요.

  **절대 이렇게 하지 마세요 (유효하지 않음)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  대신 **항상** 이렇게 하세요:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx는 `{` 또는 `}`와 같은 리터럴 중괄호를 삽입하려면 특별한 태그 주석이 필요합니다. `<pre>` 또는 `<code>` 블록에서 페이지에 텍스트 코드 스니펫을 표시하려면 부모 태그에 `phx-no-curly-interpolation`으로 주석을 *반드시* 달아야 합니다:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  `phx-no-curly-interpolation` 주석이 달린 태그 내에서는 `{`와 `}`를 이스케이프하지 않고 사용할 수 있으며, 동적 Elixir 표현식은 여전히 `<%= ... %>` 구문으로 사용할 수 있습니다

- HEEx 클래스 속성은 리스트를 지원하지만 **항상** 리스트 `[...]` 구문을 사용해야 합니다. 클래스 리스트 구문을 사용하여 조건부로 클래스를 추가할 수 있으며, **여러 클래스 값에 대해서는 항상 이렇게 하세요**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  그리고 위에서 한 것처럼 `{...}` 표현식 내부의 `if`를 **항상** 괄호로 감싸세요 (`if(@other_condition, do: "...", else: "...")`)

  그리고 **절대** 이렇게 하지 마세요. 유효하지 않습니다 (`[`와 `]`가 누락됨):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => 유효하지 않은 HEEx 속성 구문에서 컴파일 구문 오류 발생

- 템플릿 콘텐츠 생성을 위해 `<% Enum.each %>` 또는 비for 컴프리헨션을 **절대** 사용하지 마세요. 대신 **항상** `<%= for item <- @collection do %>`를 사용하세요
- HEEx HTML 주석은 `<%!-- comment --%>`를 사용합니다. 템플릿 주석에는 **항상** HEEx HTML 주석 구문을 사용하세요 (`<%!-- comment --%>`)
- HEEx는 `{...}`와 `<%= ... %>`를 통한 보간을 허용하지만, `<%= %>`는 **태그 본문 내에서만** 작동합니다. 태그 속성 내 보간과 태그 본문 내 값 보간에는 **항상** `{...}` 구문을 사용하세요. 태그 본문 내 블록 구조(if, cond, case, for) 보간에는 **항상** `<%= ... %>`를 사용하세요.

  **항상** 이렇게 하세요:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  그리고 **절대** 이렇게 하지 마세요 – 프로그램이 구문 오류로 종료됩니다:

      <%!-- 이것은 유효하지 않습니다. 절대 이렇게 하지 마세요 --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView 가이드라인

- 더 이상 사용되지 않는 `live_redirect`와 `live_patch` 함수를 **절대** 사용하지 마세요. 대신 템플릿에서는 **항상** `<.link navigate={href}>`와 `<.link patch={href}>`를 사용하고, LiveView에서는 `push_navigate`와 `push_patch` 함수를 사용하세요
- 강력하고 구체적인 필요가 있지 않는 한 **LiveComponent를 피하세요**
- LiveView는 `AppWeb.WeatherLive`와 같이 `Live` 접미사를 사용하여 명명해야 합니다. 라우터에 LiveView 라우트를 추가할 때, 기본 `:browser` 범위는 **이미** `AppWeb` 모듈로 별칭이 지정되어 있으므로 `live "/weather", WeatherLive`만 하면 됩니다

### LiveView 스트림

- 메모리 팽창과 런타임 종료를 피하기 위해 일반 리스트를 할당하는 대신 컬렉션에 **항상** LiveView 스트림을 사용하세요:
  - N개 항목의 기본 추가 - `stream(socket, :messages, [new_msg])`
  - 새 항목으로 스트림 재설정 - `stream(socket, :messages, [new_msg], reset: true)` (예: 항목 필터링용)
  - 스트림에 앞에 추가 - `stream(socket, :messages, [new_msg], at: -1)`
  - 항목 삭제 - `stream_delete(socket, :messages, msg)`

- LiveView에서 `stream/3` 인터페이스를 사용할 때, LiveView 템플릿은 1) 부모 요소에 항상 `phx-update="stream"`을 설정하고, `id="messages"`와 같은 부모 요소에 DOM id를 설정해야 하며 2) `@streams.stream_name` 컬렉션을 소비하고 id를 각 자식의 DOM id로 사용해야 합니다. LiveView에서 `stream(socket, :messages, [new_msg])`와 같은 호출의 경우, 템플릿은 다음과 같습니다:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView 스트림은 *열거 가능하지 않으므로* `Enum.filter/2`나 `Enum.reject/2`를 사용할 수 없습니다. 대신 UI에서 항목 목록을 필터링, 정리 또는 새로 고침하려면 **데이터를 다시 가져와서 reset: true를 전달하여 전체 스트림 컬렉션을 다시 스트리밍해야 합니다**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # 필터를 기반으로 메시지를 다시 가져옴
        messages = list_messages(filter)

        {:noreply,
         socket
         |> assign(:messages_empty?, messages == [])
         # 새 메시지로 스트림 재설정
         |> stream(:messages, messages, reset: true)}
      end

- LiveView 스트림은 *카운팅이나 빈 상태를 지원하지 않습니다*. 카운트를 표시해야 하는 경우 별도의 할당을 사용하여 추적해야 합니다. 빈 상태의 경우 Tailwind 클래스를 사용할 수 있습니다:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">아직 작업이 없습니다</div>
        <div :for={{id, task} <- @stream.tasks} id={id}>
          {task.name}
        </div>
      </div>

  위의 방법은 빈 상태가 스트림 for-컴프리헨션과 함께 유일한 HTML 블록인 경우에만 작동합니다.

- 스트리밍된 항목 내부의 콘텐츠를 변경해야 하는 할당을 업데이트할 때, 업데이트된 할당과 함께 항목을 다시 스트리밍해야 합니다:

      def handle_event("edit_message", %{"message_id" => message_id}, socket) do
        message = Chat.get_message!(message_id)
        edit_form = to_form(Chat.change_message(message, %{content: message.content}))

        # @editing_message_id 토글 로직이 해당 스트림 항목에 적용되도록 메시지를 다시 삽입
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(:editing_message_id, String.to_integer(message_id))
         |> assign(:edit_form, edit_form)}
      end

  그리고 템플릿에서:

      <div id="messages" phx-update="stream">
        <div :for={{id, message} <- @streams.messages} id={id} class="flex group">
          {message.username}
          <%= if @editing_message_id == message.id do %>
            <%!-- 편집 모드 --%>
            <.form for={@edit_form} id="edit-form-#{message.id}" phx-submit="save_edit">
              ...
            </.form>
          <% end %>
        </div>
      </div>

- 컬렉션에 더 이상 사용되지 않는 `phx-update="append"` 또는 `phx-update="prepend"`를 **절대** 사용하지 마세요

### LiveView JavaScript 상호 운용

- `phx-hook="MyHook"`을 사용하고 해당 JS 훅이 자체 DOM을 관리할 때마다 `phx-update="ignore"` 속성도 **반드시** 설정해야 합니다
- 컴파일러 오류가 발생하지 않도록 `phx-hook`과 함께 **항상** 고유한 DOM id를 제공하세요

LiveView 훅에는 두 가지 종류가 있습니다. 1) HEEx 내부에 정의된 "인라인" 스크립트용 공동 배치 js 훅, 2) JavaScript 객체 리터럴이 정의되고 `LiveSocket` 생성자에 전달되는 외부 `phx-hook` 주석.

#### 인라인 공동 배치 js 훅

LiveView와 호환되지 않으므로 heex에서 원시 임베디드 `<script>` 태그를 **절대** 작성하지 마세요.
대신, **템플릿 내부에서 스크립트를 작성할 때 항상 공동 배치 js 훅 스크립트 태그(`:type={Phoenix.LiveView.ColocatedHook}`)를 사용하세요**:

    <input type="text" name="user[phone_number]" id="user-phone-number" phx-hook=".PhoneNumber" />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
      export default {
        mounted() {
          this.el.addEventListener("input", e => {
            let match = this.el.value.replace(/\D/g, "").match(/^(\d{3})(\d{3})(\d{4})$/)
            if(match) {
              this.el.value = `${match[1]}-${match[2]}-${match[3]}`
            }
          })
        }
      }
    </script>

- 공동 배치 훅은 자동으로 app.js 번들에 통합됩니다
- 공동 배치 훅 이름은 **항상** `.` 접두사로 시작해야 합니다. 예: `.PhoneNumber`

#### 외부 phx-hook

외부 JS 훅(`<div id="myhook" phx-hook="MyHook">`)은 `assets/js/`에 배치되고 LiveSocket 생성자에 전달되어야 합니다:

    const MyHook = {
      mounted() { ... }
    }
    let liveSocket = new LiveSocket("/live", Socket, {
      hooks: { MyHook }
    });

#### 클라이언트와 서버 간 이벤트 푸시

phx-hook이 처리할 이벤트/데이터를 클라이언트에 푸시해야 할 때 LiveView의 `push_event/3`를 사용하세요.
이벤트를 푸시할 때 `push_event/3`에서 소켓을 **항상** 반환하거나 재바인딩하세요:

    # 푸시될 이벤트 상태를 유지하도록 소켓을 재바인딩
    socket = push_event(socket, "my_event", %{...})

    # 또는 수정된 소켓을 직접 반환:
    def handle_event("some_event", _, socket) do
      {:noreply, push_event(socket, "my_event", %{...})}
    end

푸시된 이벤트는 JS 훅에서 `this.handleEvent`로 받을 수 있습니다:

    mounted() {
      this.handleEvent("my_event", data => console.log("from server:", data));
    }

클라이언트는 `this.pushEvent`로 서버에 이벤트를 푸시하고 응답을 받을 수도 있습니다:

    mounted() {
      this.el.addEventListener("click", e => {
        this.pushEvent("my_event", { one: 1 }, reply => console.log("got reply from server:", reply));
      })
    }

서버에서는 다음과 같이 처리됩니다:

    def handle_event("my_event", %{"one" => 1}, socket) do
      {:reply, %{two: 2}, socket}
    end

### LiveView 테스트

- 어설션을 위해 `Phoenix.LiveViewTest` 모듈과 `LazyHTML`(포함됨)을 사용하세요
- 폼 테스트는 `Phoenix.LiveViewTest`의 `render_submit/2`와 `render_change/2` 함수로 구동됩니다
- 주요 테스트 케이스를 작고 격리된 파일로 분할하는 단계별 테스트 계획을 세우세요. 콘텐츠가 존재하는지 확인하는 간단한 테스트부터 시작하여 점진적으로 상호작용 테스트를 추가할 수 있습니다
- `element/2`, `has_element/2`, 선택자 등과 같은 `Phoenix.LiveViewTest` 함수에 대해 **항상 LiveView 템플릿에 추가한 주요 요소 ID를 테스트에서 참조하세요**
- 원시 HTML에 대해 **절대** 테스트하지 마세요. **항상** `element/2`, `has_element/2` 등을 사용하세요: `assert has_element?(view, "#my-form")`
- 변경될 수 있는 텍스트 콘텐츠 테스트에 의존하는 대신 주요 요소의 존재를 테스트하는 것을 선호하세요
- 구현 세부사항보다는 결과 테스트에 집중하세요
- `<.form>`과 같은 `Phoenix.Component` 함수가 예상과 다른 HTML을 생성할 수 있음을 인식하세요. 예상하는 정신적 모델이 아닌 출력 HTML 구조에 대해 테스트하세요
- 요소 선택자로 테스트 실패에 직면할 때, 실제 HTML을 출력하는 디버그 문을 추가하되 `LazyHTML` 선택자를 사용하여 출력을 제한하세요:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### 폼 처리

#### 매개변수에서 폼 생성

`handle_event` 매개변수를 기반으로 폼을 생성하려면:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

`to_form/1`에 맵을 전달하면, 해당 맵이 문자열 키를 가질 것으로 예상되는 폼 매개변수를 포함한다고 가정합니다.

매개변수를 중첩하기 위해 이름을 지정할 수도 있습니다:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### 체인지셋에서 폼 생성

체인지셋을 사용할 때, 기본 데이터, 폼 매개변수, 오류가 여기서 검색됩니다. `:as` 옵션도 자동으로 계산됩니다. 예를 들어 사용자 스키마가 있는 경우:

    defmodule MyApp.Users.User do
      use Ecto.Schema
      ...
    end

그런 다음 `to_form`에 전달할 체인지셋을 생성합니다:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

폼이 제출되면 매개변수는 `%{"user" => user_params}` 하에서 사용할 수 있습니다.

템플릿에서 폼 할당은 `<.form>` 함수 컴포넌트에 전달될 수 있습니다:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

`id="todo-form"`과 같이 폼에 항상 명시적이고 고유한 DOM ID를 부여하세요.

#### 폼 오류 방지

LiveView에서 `to_form/2`를 통해 할당된 폼을 **항상** 사용하고, 템플릿에서 `<.input>` 컴포넌트를 사용하세요. 템플릿에서 **항상 이렇게 폼에 액세스하세요**:

    <%!-- 항상 이렇게 하세요 (유효함) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

그리고 **절대** 이렇게 하지 마세요:

    <%!-- 절대 이렇게 하지 마세요 (유효하지 않음) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- 오류를 일으킬 수 있으므로 템플릿에서 체인지셋에 액세스하는 것은 **금지**됩니다
- 템플릿에서 `<.form let={f} ...>`를 **절대** 사용하지 마세요. 대신 **항상 `<.form for={@form} ...>`를 사용**한 다음 `@form[:field]`에서와 같이 폼 할당에서 모든 폼 참조를 구동하세요. UI는 체인지셋에서 파생된 LiveView 모듈에서 할당된 `to_form/2`에 의해 **항상** 구동되어야 합니다
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->