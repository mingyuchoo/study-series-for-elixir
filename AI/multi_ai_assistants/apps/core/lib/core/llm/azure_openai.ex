defmodule Core.LLM.AzureOpenAI do
  @moduledoc """
  Azure OpenAI API 채팅 완성 클라이언트.
  에이전트 동작을 위한 함수 호출(Function Calling)을 지원합니다.
  """

  require Logger
  alias Core.Agent.RunStore
  alias Core.Agent.Telemetry

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

  def embed_texts(texts, opts \\ []) when is_list(texts) and texts != [] do
    deployment =
      Keyword.get(opts, :model) || Application.get_env(:core, :azure_openai_embedding_deployment)

    with true <- is_binary(deployment) and deployment != "",
         {:ok, config} <- get_config(),
         :ok <- RunStore.reserve_model_call(Process.get(:agent_run_id)),
         {:ok, %{status: 200, body: %{"data" => data} = response_body}} <-
           Req.post("#{String.trim_trailing(config.endpoint, "/")}/openai/v1/embeddings",
             json: %{model: deployment, input: texts},
             headers: [{"api-key", config.api_key}],
             receive_timeout: 120_000
           ) do
      vectors =
        data
        |> Enum.sort_by(& &1["index"])
        |> Enum.map(& &1["embedding"])

      dimensions =
        Enum.map(vectors, fn vector -> if is_list(vector), do: length(vector), else: 0 end)

      if length(vectors) == length(texts) and
           Enum.all?(vectors, fn vector ->
             is_list(vector) and vector != [] and Enum.all?(vector, &is_number/1)
           end) and
           length(Enum.uniq(dimensions)) == 1 do
        RunStore.add_tokens(Process.get(:agent_run_id), response_body["usage"])
        {:ok, vectors, deployment}
      else
        {:error, :invalid_embedding_response}
      end
    else
      false -> {:error, :embedding_not_configured}
      {:ok, response} -> {:error, {:embedding_http_error, response.status}}
      error -> error
    end
  end

  @spec chat_completion([message()], completion_opts()) :: {:ok, map()} | {:error, term()}
  def chat_completion(messages, opts \\ []) do
    with {:ok, config} <- get_config(),
         :ok <- RunStore.reserve_model_call(Process.get(:agent_run_id)) do
      model = Keyword.get(opts, :model, config.deployment)

      # GPT-5 계열 Azure 배포는 temperature 기본값 1.0만 허용하는 경우가 있다.
      default_temperature = 1.0

      body =
        %{
          messages: messages,
          temperature: Keyword.get(opts, :temperature, default_temperature),
          max_completion_tokens: Keyword.get(opts, :max_completion_tokens, 4096)
        }
        |> maybe_add_tools(Keyword.get(opts, :tools))
        |> maybe_add_tool_choice(Keyword.get(opts, :tool_choice))

      url = build_url(config, model)

      response =
        Telemetry.measure(:model, %{run_id: Process.get(:agent_run_id), model: model}, fn ->
          Req.post(url,
            json: body,
            headers: [
              {"api-key", config.api_key},
              {"Content-Type", "application/json"}
            ],
            receive_timeout: 120_000
          )
        end)

      case response do
        {:ok, %{status: 200, body: response_body}} ->
          RunStore.add_tokens(Process.get(:agent_run_id), response_body["usage"])
          {:ok, parse_response(response_body)}

        {:ok, %{status: status, body: error_body}} ->
          Logger.error("Azure OpenAI API error: #{status} - #{inspect(error_body)}")
          {:error, {:api_error, status, error_body}}

        {:error, reason} ->
          Logger.error("Azure OpenAI request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end

  @spec stream_chat_completion([message()], completion_opts(), (map() -> any())) ::
          {:ok, map()} | {:error, term()}
  def stream_chat_completion(messages, opts \\ [], callback) do
    with {:ok, config} <- get_config(),
         :ok <- RunStore.reserve_model_call(Process.get(:agent_run_id)) do
      model = Keyword.get(opts, :model, config.deployment)

      # GPT-5 계열 Azure 배포는 temperature 기본값 1.0만 허용하는 경우가 있다.
      default_temperature = 1.0

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

      Process.put(:azure_stream_buffer, "")

      try do
        Telemetry.measure(:model, %{run_id: Process.get(:agent_run_id), model: model}, fn ->
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
        end)
      after
        Process.delete(:azure_stream_buffer)
      end
    end
  end

  # 비공개 함수들

  defp get_config do
    config = %{
      endpoint: Application.get_env(:core, :azure_openai_endpoint),
      api_key: Application.get_env(:core, :azure_openai_api_key),
      api_version: Application.get_env(:core, :azure_openai_api_version, @default_api_version),
      # Azure 의 URL 경로는 모델명이 아니라 "배포(deployment) 이름" 이므로
      # 환경 변수로 노출해 사용자가 자신의 리소스에 맞게 지정할 수 있게 한다.
      deployment: Application.get_env(:core, :azure_openai_deployment, @default_model)
    }

    cond do
      blank?(config.endpoint) ->
        {:error, {:missing_config, :azure_openai_endpoint}}

      blank?(config.api_key) ->
        {:error, {:missing_config, :azure_openai_api_key}}

      true ->
        {:ok, config}
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false

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
    parts = String.split(Process.get(:azure_stream_buffer, "") <> chunk, "\n")
    {lines, [remaining]} = Enum.split(parts, -1)
    Process.put(:azure_stream_buffer, remaining)

    lines
    |> Enum.map(&String.trim_trailing(&1, "\r"))
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.each(&process_stream_line(&1, callback))

    {:cont, acc}
  end

  defp process_stream_line(line, callback) do
    case String.trim_leading(line, "data: ") do
      "[DONE]" -> :ok
      json_str -> decode_stream_json(json_str, callback)
    end
  end

  defp decode_stream_json(json_str, callback) do
    case Jason.decode(json_str) do
      {:ok, data} ->
        RunStore.add_tokens(Process.get(:agent_run_id), data["usage"])
        callback.(data)

      _ ->
        :ok
    end
  end
end
