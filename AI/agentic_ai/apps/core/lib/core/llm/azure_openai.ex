defmodule Core.LLM.AzureOpenAI do
  @moduledoc """
  Azure OpenAI API 채팅 완성 클라이언트.
  에이전트 동작을 위한 함수 호출(Function Calling)을 지원합니다.
  """

  require Logger

  @type message :: %{role: String.t(), content: String.t()}
  @type tool :: %{type: String.t(), function: map()}
  @type completion_opts :: [
          model: String.t(),
          temperature: float(),
          max_completion_tokens: integer(),
          tools: [tool()],
          tool_choice: String.t() | map()
        ]

  @default_model "gpt-5-mini"
  @default_api_version "2024-10-21"

  @spec chat_completion([message()], completion_opts()) :: {:ok, map()} | {:error, term()}
  def chat_completion(messages, opts \\ []) do
    config = get_config()
    model = Keyword.get(opts, :model, @default_model)

    # GPT-5-mini는 temperature 1.0만 지원
    default_temperature = if model == "gpt-5-mini", do: 1.0, else: 0.7

    body =
      %{
        messages: messages,
        temperature: Keyword.get(opts, :temperature, default_temperature),
        max_completion_tokens: Keyword.get(opts, :max_completion_tokens, 4096)
      }
      |> maybe_add_tools(Keyword.get(opts, :tools))
      |> maybe_add_tool_choice(Keyword.get(opts, :tool_choice))

    url = build_url(config, model)

    case Req.post(url,
           json: body,
           headers: [
             {"api-key", config.api_key},
             {"Content-Type", "application/json"}
           ],
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, parse_response(response_body)}

      {:ok, %{status: status, body: error_body}} ->
        Logger.error("Azure OpenAI API error: #{status} - #{inspect(error_body)}")
        {:error, {:api_error, status, error_body}}

      {:error, reason} ->
        Logger.error("Azure OpenAI request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  @spec stream_chat_completion([message()], completion_opts(), (map() -> any())) ::
          {:ok, map()} | {:error, term()}
  def stream_chat_completion(messages, opts \\ [], callback) do
    config = get_config()
    model = Keyword.get(opts, :model, @default_model)

    # GPT-5-mini는 temperature 1.0만 지원
    default_temperature = if model == "gpt-5-mini", do: 1.0, else: 0.7

    body =
      %{
        messages: messages,
        temperature: Keyword.get(opts, :temperature, default_temperature),
        max_completion_tokens: Keyword.get(opts, :max_completion_tokens, 4096),
        stream: true
      }
      |> maybe_add_tools(Keyword.get(opts, :tools))
      |> maybe_add_tool_choice(Keyword.get(opts, :tool_choice))

    url = build_url(config, model)

    Req.post(url,
      json: body,
      headers: [
        {"api-key", config.api_key},
        {"Content-Type", "application/json"}
      ],
      receive_timeout: 120_000,
      into: fn {:data, chunk}, acc ->
        process_stream_chunk(chunk, callback, acc)
      end
    )
  end

  # 비공개 함수들

  defp get_config do
    %{
      endpoint: Application.get_env(:core, :azure_openai_endpoint),
      api_key: Application.get_env(:core, :azure_openai_api_key),
      api_version: Application.get_env(:core, :azure_openai_api_version, @default_api_version)
    }
  end

  defp build_url(config, model) do
    "#{config.endpoint}/openai/deployments/#{model}/chat/completions?api-version=#{config.api_version}"
  end

  defp maybe_add_tools(body, nil), do: body
  defp maybe_add_tools(body, []), do: body
  defp maybe_add_tools(body, tools), do: Map.put(body, :tools, tools)

  defp maybe_add_tool_choice(body, nil), do: body
  defp maybe_add_tool_choice(body, choice), do: Map.put(body, :tool_choice, choice)

  defp parse_response(%{"choices" => [choice | _]} = response) do
    message = choice["message"]

    %{
      content: message["content"],
      role: message["role"],
      tool_calls: message["tool_calls"],
      finish_reason: choice["finish_reason"],
      usage: response["usage"]
    }
  end

  defp process_stream_chunk(chunk, callback, acc) do
    chunk
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.each(fn line ->
      case String.trim_leading(line, "data: ") do
        "[DONE]" ->
          :ok

        json_str ->
          case Jason.decode(json_str) do
            {:ok, data} -> callback.(data)
            _ -> :ok
          end
      end
    end)

    {:cont, acc}
  end
end
