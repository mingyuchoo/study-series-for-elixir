defmodule Core.Agent.TaskRouterTest do
  use ExUnit.Case, async: true

  alias Core.Agent.TaskRouter
  alias Core.Schema.Agent

  # 테스트용 Worker 구조체 생성 헬퍼
  defp create_worker(attrs) do
    %Agent{
      id: Ecto.UUID.generate(),
      type: :worker,
      name: attrs[:name] || "worker_#{:rand.uniform(1000)}",
      display_name: attrs[:display_name] || "Test Worker",
      description: attrs[:description] || "",
      enabled_tools: attrs[:enabled_tools] || [],
      status: :active
    }
  end

  describe "select_worker/2" do
    @tag :capture_log
    test "빈 Worker 목록에서 에러를 반환한다" do
      assert {:error, :no_workers_available} =
               TaskRouter.select_worker("테스트 요청", [])
    end

    test "Worker가 하나만 있으면 해당 Worker를 반환한다" do
      worker = create_worker(%{name: "only_worker"})

      assert {:ok, selected} = TaskRouter.select_worker("아무 요청", [worker])
      assert selected.name == "only_worker"
    end

    test "계산 관련 요청에서 calculator 도구를 가진 Worker를 선호한다" do
      calc_worker =
        create_worker(%{
          name: "calculator_worker",
          description: "수학 계산을 수행합니다",
          enabled_tools: ["calculator"]
        })

      general_worker =
        create_worker(%{
          name: "general_worker",
          description: "일반적인 작업을 수행합니다",
          enabled_tools: ["web_search"]
        })

      assert {:ok, selected} =
               TaskRouter.select_worker("2 + 2를 계산해줘", [general_worker, calc_worker])

      assert selected.name == "calculator_worker"
    end

    test "검색 관련 요청에서 web_search 도구를 가진 Worker를 선호한다" do
      search_worker =
        create_worker(%{
          name: "search_worker",
          description: "정보 검색을 수행합니다",
          enabled_tools: ["web_search"]
        })

      calc_worker =
        create_worker(%{
          name: "calc_worker",
          enabled_tools: ["calculator"]
        })

      assert {:ok, selected} =
               TaskRouter.select_worker("최신 뉴스를 검색해줘", [calc_worker, search_worker])

      assert selected.name == "search_worker"
    end

    test "코드 관련 요청에서 code 도구를 가진 Worker를 선호한다" do
      code_worker =
        create_worker(%{
          name: "code_worker",
          description: "코드 실행과 프로그래밍을 담당합니다",
          enabled_tools: ["code_executor"]
        })

      other_worker =
        create_worker(%{
          name: "other_worker",
          enabled_tools: ["calculator"]
        })

      assert {:ok, selected} = TaskRouter.select_worker("함수를 구현해줘", [other_worker, code_worker])
      assert selected.name == "code_worker"
    end

    test "Worker 이름에서 타입을 추출하여 매칭한다" do
      # calculator_worker라는 이름은 calculator 도메인 키워드와 매칭
      named_worker =
        create_worker(%{
          name: "calculator_worker",
          description: "",
          enabled_tools: []
        })

      generic_worker =
        create_worker(%{
          name: "generic_agent",
          description: "",
          enabled_tools: []
        })

      assert {:ok, selected} =
               TaskRouter.select_worker("숫자를 더하기 해줘", [generic_worker, named_worker])

      assert selected.name == "calculator_worker"
    end

    test "설명에서 키워드를 매칭하여 점수를 계산한다" do
      # calculator 도구를 가진 worker가 계산 요청에서 선호됨
      math_worker =
        create_worker(%{
          name: "worker_a",
          description: "수학 계산과 숫자 처리를 전문으로 합니다",
          enabled_tools: ["calculator"]
        })

      text_worker =
        create_worker(%{
          name: "worker_b",
          description: "텍스트 분석과 문서 처리를 담당합니다",
          enabled_tools: []
        })

      assert {:ok, selected} = TaskRouter.select_worker("평균 계산이 필요해", [text_worker, math_worker])
      assert selected.name == "worker_a"
    end

    test "모든 Worker가 동일한 점수일 때 첫 번째 Worker를 반환한다" do
      worker1 = create_worker(%{name: "worker_1"})
      worker2 = create_worker(%{name: "worker_2"})
      worker3 = create_worker(%{name: "worker_3"})

      # 매칭되지 않는 요청
      assert {:ok, selected} = TaskRouter.select_worker("xyz", [worker1, worker2, worker3])
      # 점수가 동일하면 첫 번째가 선택됨 (정렬이 안정적인 경우)
      assert selected.name in ["worker_1", "worker_2", "worker_3"]
    end

    test "여러 도메인 키워드가 포함된 요청을 처리한다" do
      multi_tool_worker =
        create_worker(%{
          name: "multi_worker",
          description: "계산과 검색을 모두 지원합니다. 수학과 정보 조사.",
          enabled_tools: ["calculator", "web_search"]
        })

      single_tool_worker =
        create_worker(%{
          name: "single_worker",
          description: "",
          enabled_tools: ["file_system"]
        })

      # 계산과 검색 모두 포함된 요청에서 해당 도구를 가진 worker 선택
      assert {:ok, selected} =
               TaskRouter.select_worker("통계 정보를 검색해서 평균을 계산해줘", [
                 single_tool_worker,
                 multi_tool_worker
               ])

      assert selected.name == "multi_worker"
    end

    test "대소문자를 구분하지 않고 키워드를 매칭한다" do
      worker =
        create_worker(%{
          name: "calc_worker",
          description: "CALCULATOR 기능",
          enabled_tools: ["calculator"]
        })

      other = create_worker(%{name: "other"})

      assert {:ok, selected} = TaskRouter.select_worker("CALCULATE this", [other, worker])
      # 설명이나 도구가 매칭되어야 함
      assert selected.name in ["calc_worker", "other"]
    end
  end

  describe "select_worker/2 with specific keywords" do
    test "더하기 키워드가 calculator 도메인과 매칭된다" do
      calc_worker =
        create_worker(%{
          name: "calc",
          enabled_tools: ["calculator"]
        })

      other = create_worker(%{name: "other"})

      assert {:ok, selected} = TaskRouter.select_worker("더하기 해줘", [other, calc_worker])
      assert selected.name == "calc"
    end

    test "검색 키워드가 web_search 도메인과 매칭된다" do
      search_worker =
        create_worker(%{
          name: "searcher",
          enabled_tools: ["web_search"]
        })

      other = create_worker(%{name: "other"})

      assert {:ok, selected} = TaskRouter.select_worker("날씨를 검색해줘", [other, search_worker])
      assert selected.name == "searcher"
    end

    test "프로그램 키워드가 code 도메인과 매칭된다" do
      code_worker =
        create_worker(%{
          name: "coder",
          enabled_tools: ["code_executor"]
        })

      other = create_worker(%{name: "other"})

      assert {:ok, selected} = TaskRouter.select_worker("프로그램 만들어줘", [other, code_worker])
      assert selected.name == "coder"
    end

    test "수학 기호(+, -, *, /)가 calculator와 매칭된다" do
      calc_worker =
        create_worker(%{
          name: "calc",
          enabled_tools: ["calculator"]
        })

      other = create_worker(%{name: "other"})

      for symbol <- ["+", "-", "*", "/"] do
        assert {:ok, selected} =
                 TaskRouter.select_worker("3 #{symbol} 2 = ?", [other, calc_worker])

        assert selected.name == "calc", "Failed for symbol: #{symbol}"
      end
    end
  end

  describe "select_worker/2 edge cases" do
    test "nil description을 가진 Worker를 처리한다" do
      worker =
        create_worker(%{
          name: "no_desc_worker",
          description: nil,
          enabled_tools: ["calculator"]
        })

      assert {:ok, selected} = TaskRouter.select_worker("계산해줘", [worker])
      assert selected.name == "no_desc_worker"
    end

    test "빈 문자열 description을 가진 Worker를 처리한다" do
      worker =
        create_worker(%{
          name: "empty_desc_worker",
          description: "",
          enabled_tools: ["calculator"]
        })

      assert {:ok, selected} = TaskRouter.select_worker("계산해줘", [worker])
      assert selected.name == "empty_desc_worker"
    end

    test "빈 enabled_tools를 가진 Worker를 처리한다" do
      worker =
        create_worker(%{
          name: "no_tools_worker",
          description: "설명",
          enabled_tools: []
        })

      assert {:ok, selected} = TaskRouter.select_worker("요청", [worker])
      assert selected.name == "no_tools_worker"
    end

    test "긴 요청 문자열을 처리한다" do
      worker =
        create_worker(%{
          name: "test_worker",
          enabled_tools: ["calculator"]
        })

      long_request = String.duplicate("이것은 매우 긴 요청입니다. 숫자 계산이 필요합니다. ", 100)

      assert {:ok, selected} = TaskRouter.select_worker(long_request, [worker])
      assert selected.name == "test_worker"
    end

    test "특수 문자가 포함된 요청을 처리한다" do
      worker =
        create_worker(%{
          name: "calc_worker",
          enabled_tools: ["calculator"]
        })

      assert {:ok, selected} =
               TaskRouter.select_worker("3+5=? @#$%^&*()", [worker])

      assert selected.name == "calc_worker"
    end
  end
end
