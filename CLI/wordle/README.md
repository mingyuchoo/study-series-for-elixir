# 🎯 Wordle Game (Elixir)

Elixir로 구현한 Wordle 스타일 단어 맞추기 게임입니다.

## 게임 규칙

- 5글자 영어 단어를 맞추는 게임
- 6번의 기회가 주어집니다
- 각 시도마다 힌트가 제공됩니다:
  - 🟩 **초록**: 정확한 위치에 정확한 글자
  - 🟨 **노랑**: 단어에 포함되지만 다른 위치
  - ⬜ **회색**: 단어에 포함되지 않음

## 실행 방법

### 대화형 모드 (IEx)

```bash
cd wordle
mix deps.get
iex -S mix
```

```elixir
# 게임 시작
game = WordleGame.new_game()

# 단어 추측
{:ok, result, game} = WordleGame.guess(game, "hello")

# 결과 확인: [:correct, :present, :absent, ...]
```

### CLI 모드

```bash
cd wordle
mix deps.get
mix escript.build
./wordle_game
```

또는

```bash
mix run -e "WordleGame.CLI.main()"
```

## 프로젝트 구조

```
wordle/
├── lib/
│   ├── wordle_game.ex           # 메인 모듈
│   └── wordle_game/
│       ├── cli.ex               # CLI 인터페이스
│       ├── game.ex              # 게임 로직
│       └── words.ex             # 단어 목록
├── test/
│   ├── test_helper.exs
│   └── wordle_game_test.exs     # 테스트
├── mix.exs                       # 프로젝트 설정
└── README.md
```

## API

### `WordleGame.new_game/0`
새 게임을 시작합니다.

### `WordleGame.guess/2`
단어를 추측합니다. 결과:
- `{:ok, result, game}` - 성공
- `{:error, reason, game}` - 실패 (`:invalid_word`, `:already_guessed`, `:game_over`)

### `WordleGame.game_over?/1`
게임이 끝났는지 확인합니다.

### `WordleGame.won?/1`
게임에서 이겼는지 확인합니다.

## 테스트

```bash
mix test
```

## 게임 플레이 예시

```
╔═══════════════════════════════════════╗
║         🎯 WORDLE GAME 🎯             ║
║     5글자 영어 단어 맞추기 게임       ║
╠═══════════════════════════════════════╣
║  🟩 = 정확한 위치                     ║
║  🟨 = 단어에 포함 (다른 위치)         ║
║  ⬜ = 단어에 없음                     ║
╚═══════════════════════════════════════╝

남은 기회: 6번
단어 입력: crane

│ ⬜🟨⬜⬜🟨 │
│ C  R  A  N  E │

남은 기회: 5번
단어 입력: steel

│ 🟩🟩🟩🟩🟩 │
│ S  T  E  E  L │

🎉 축하합니다! 정답입니다! 🎉
2번 만에 맞추셨습니다!
```

## 특별 명령어

게임 중 다음 명령어를 사용할 수 있습니다:
- `hint` - 힌트 받기 (정답에 포함된 글자 하나를 알려줍니다)
- `quit` 또는 `exit` - 게임 종료

## 라이선스

MIT
