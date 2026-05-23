defmodule AgenticAiAgent.LLM.AzureOpenAI do
  @moduledoc """
  Azure OpenAI Chat Completions adapter.

  Config (typically set in `config/runtime.exs` from env vars):

      config :agentic_ai_agent, AgenticAiAgent.LLM.AzureOpenAI,
        endpoint: "https://my-resource.openai.azure.com",
        api_key: "...",
        deployment: "gpt-4o-mini",
        api_version: "2024-10-21",
        receive_timeout: 60_000

  Endpoint URL is built as:

      {endpoint}/openai/deployments/{deployment}/chat/completions?api-version={version}

  Auth header is `api-key: ...` (Azure-specific, NOT `Authorization: Bearer`).
  """

  @behaviour AgenticAiAgent.LLM.Adapter

  alias AgenticAiAgent.LLM.Response

  @default_api_version "2024-10-21"
  @default_timeout_ms 60_000

  @impl true
  def chat(messages, opts \\ []) do
    with {:ok, cfg} <- fetch_config(),
         {:ok, body} <- build_body(messages, opts),
         {:ok, resp} <- post(cfg, body) do
      parse_response(resp)
    end
  end

  # ----- Request construction -----

  defp build_body(messages, opts) do
    messages = maybe_prepend_system(messages, Keyword.get(opts, :system))

    # Reasoning models (gpt-5 family, o-series, etc.) reject any non-default
    # `temperature` and use `max_completion_tokens` instead of `max_tokens`.
    # Only include either field when the caller explicitly opts in.
    body =
      %{"messages" => messages}
      |> put_if(Keyword.get(opts, :temperature), "temperature")
      |> put_if(Keyword.get(opts, :max_tokens), "max_tokens")
      |> put_if(Keyword.get(opts, :max_completion_tokens), "max_completion_tokens")
      |> put_tools(Keyword.get(opts, :tools))
      |> put_tool_choice(Keyword.get(opts, :tool_choice))

    {:ok, body}
  end

  defp maybe_prepend_system(messages, nil), do: messages

  defp maybe_prepend_system([%{"role" => "system"} | _] = messages, _system),
    do: messages

  defp maybe_prepend_system(messages, system) when is_binary(system),
    do: [%{"role" => "system", "content" => system} | messages]

  defp put_if(map, nil, _key), do: map
  defp put_if(map, value, key), do: Map.put(map, key, value)

  defp put_tools(body, nil), do: body
  defp put_tools(body, []), do: body

  defp put_tools(body, tools) when is_list(tools) do
    Map.put(body, "tools", Enum.map(tools, &to_openai_tool/1))
  end

  defp to_openai_tool(%{"name" => name} = t) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => Map.get(t, "description", ""),
        "parameters" => Map.get(t, "input_schema", %{"type" => "object"})
      }
    }
  end

  defp put_tool_choice(body, nil), do: body
  defp put_tool_choice(body, choice), do: Map.put(body, "tool_choice", choice)

  # ----- HTTP -----

  defp post(cfg, body) do
    url =
      "#{cfg.endpoint}/openai/deployments/#{cfg.deployment}/chat/completions?api-version=#{cfg.api_version}"

    headers = [
      {"api-key", cfg.api_key},
      {"content-type", "application/json"}
    ]

    case Req.post(url,
           headers: headers,
           json: body,
           receive_timeout: cfg.receive_timeout
         ) do
      {:ok, %{status: status, body: resp_body}} when status in 200..299 ->
        {:ok, resp_body}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:http_error, status, resp_body}}

      {:error, %{__exception__: true} = exc} ->
        {:error, {:transport_error, Exception.message(exc)}}

      {:error, reason} ->
        {:error, {:transport_error, reason}}
    end
  end

  # ----- Response normalization -----

  defp parse_response(%{"choices" => [choice | _]} = raw) do
    msg = Map.get(choice, "message", %{})
    tool_calls = msg |> Map.get("tool_calls", []) |> Enum.map(&normalize_tool_call/1)

    {:ok,
     %Response{
       role: Map.get(msg, "role", "assistant"),
       content: Map.get(msg, "content"),
       tool_calls: tool_calls,
       finish_reason: Map.get(choice, "finish_reason"),
       usage: Map.get(raw, "usage"),
       model: Map.get(raw, "model") || infer_model_from_config(),
       raw: raw
     }}
  end

  defp parse_response(other), do: {:error, {:malformed_response, other}}

  # When the provider doesn't echo the model name (rare), fall back to the
  # configured deployment.
  defp infer_model_from_config do
    case Application.get_env(:agentic_ai_agent, __MODULE__, [])[:deployment] do
      v when is_binary(v) and v != "" -> v
      _ -> nil
    end
  end

  defp normalize_tool_call(%{
         "id" => id,
         "type" => "function",
         "function" => %{"name" => name, "arguments" => args}
       }) do
    %{id: id, name: name, arguments: decode_args(args)}
  end

  defp normalize_tool_call(other) do
    %{id: Map.get(other, "id", ""), name: "unknown", arguments: %{}, raw: other}
  end

  defp decode_args(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{"_raw" => args}
    end
  end

  defp decode_args(args) when is_map(args), do: args
  defp decode_args(_), do: %{}

  # ----- Config -----

  defp fetch_config do
    cfg = Application.get_env(:agentic_ai_agent, __MODULE__, [])

    with {:ok, endpoint} <- require_key(cfg, :endpoint),
         {:ok, api_key} <- require_key(cfg, :api_key),
         {:ok, deployment} <- require_key(cfg, :deployment) do
      {:ok,
       %{
         endpoint: String.trim_trailing(endpoint, "/"),
         api_key: api_key,
         deployment: deployment,
         api_version: Keyword.get(cfg, :api_version, @default_api_version),
         receive_timeout: Keyword.get(cfg, :receive_timeout, @default_timeout_ms)
       }}
    end
  end

  defp require_key(cfg, key) do
    case Keyword.get(cfg, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_config, key}}
    end
  end
end
