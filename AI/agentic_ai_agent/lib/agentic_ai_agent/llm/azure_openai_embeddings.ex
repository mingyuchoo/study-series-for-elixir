defmodule AgenticAiAgent.LLM.AzureOpenAIEmbeddings do
  @moduledoc """
  Azure OpenAI Embeddings adapter.

  Config (typically set in `config/runtime.exs` from env vars):

      config :agentic_ai_agent, AgenticAiAgent.LLM.AzureOpenAIEmbeddings,
        endpoint: "https://my-resource.openai.azure.com",
        api_key: "...",
        deployment: "text-embedding-3-large",
        api_version: "2024-02-01",
        receive_timeout: 30_000

  URL: `{endpoint}/openai/deployments/{deployment}/embeddings?api-version=...`
  """

  @behaviour AgenticAiAgent.LLM.Embeddings

  @default_api_version "2024-02-01"
  @default_timeout_ms 30_000

  @impl true
  def embed(texts, _opts \\ []) when is_list(texts) do
    with {:ok, cfg} <- fetch_config(),
         {:ok, resp} <- post(cfg, %{"input" => texts}),
         {:ok, vectors} <- extract(resp) do
      {:ok, %{model: cfg.deployment, vectors: vectors, usage: Map.get(resp, "usage")}}
    end
  end

  # ----- HTTP -----

  defp post(cfg, body) do
    url =
      "#{cfg.endpoint}/openai/deployments/#{cfg.deployment}/embeddings?api-version=#{cfg.api_version}"

    headers = [
      {"api-key", cfg.api_key},
      {"content-type", "application/json"}
    ]

    case Req.post(url, headers: headers, json: body, receive_timeout: cfg.receive_timeout) do
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

  defp extract(%{"data" => data}) when is_list(data) do
    vectors =
      data
      |> Enum.sort_by(&Map.get(&1, "index", 0))
      |> Enum.map(&Map.fetch!(&1, "embedding"))

    {:ok, vectors}
  end

  defp extract(other), do: {:error, {:malformed_response, other}}

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
