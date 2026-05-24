defmodule AgenticAiAgent.LLM.AzureOpenAITest do
  use ExUnit.Case, async: false

  alias AgenticAiAgent.LLM.AzureOpenAI

  setup {Req.Test, :verify_on_exit!}

  setup do
    previous = Application.get_env(:agentic_ai_agent, AzureOpenAI)

    Application.put_env(:agentic_ai_agent, AzureOpenAI,
      endpoint: "https://azure-openai.test",
      api_key: "test-key",
      deployment: "gpt-5",
      api_version: "2024-10-21",
      request_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn ->
      if previous do
        Application.put_env(:agentic_ai_agent, AzureOpenAI, previous)
      else
        Application.delete_env(:agentic_ai_agent, AzureOpenAI)
      end
    end)

    :ok
  end

  test "retries without temperature when the deployment rejects non-default temperature" do
    parent = self()
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Req.Test.expect(__MODULE__, 2, fn conn ->
      body = Jason.decode!(Req.Test.raw_body(conn))
      send(parent, {:request_body, body})

      case Agent.get_and_update(counter, &{&1 + 1, &1 + 1}) do
        1 ->
          conn
          |> Plug.Conn.put_status(400)
          |> Req.Test.json(%{
            error: %{
              code: "unsupported_value",
              message:
                "Unsupported value: 'temperature' does not support 0.2 with this model. Only the default (1) value is supported.",
              param: "temperature",
              type: "invalid_request_error"
            }
          })

        2 ->
          Req.Test.json(conn, %{
            choices: [
              %{
                message: %{role: "assistant", content: "ok"},
                finish_reason: "stop"
              }
            ],
            usage: %{prompt_tokens: 1, completion_tokens: 1, total_tokens: 2},
            model: "gpt-5"
          })
      end
    end)

    assert {:ok, response} =
             AzureOpenAI.chat([%{"role" => "user", "content" => "Hello"}], temperature: 0.2)

    assert response.content == "ok"

    assert_receive {:request_body, first_body}
    assert first_body["temperature"] == 0.2

    assert_receive {:request_body, second_body}
    refute Map.has_key?(second_body, "temperature")
  end
end
