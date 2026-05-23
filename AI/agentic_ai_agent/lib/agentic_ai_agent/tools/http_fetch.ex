defmodule AgenticAiAgent.Tools.HttpFetch do
  @moduledoc """
  HTTP GET a public URL and return status + (truncated) body. Only http/https
  schemes are allowed. Bodies are truncated so the result fits the model's
  context window.
  """

  @behaviour AgenticAiAgent.Tool

  @max_body_chars 8_000
  @default_timeout_ms 8_000

  @impl true
  def name, do: "http_fetch"

  @impl true
  def description,
    do:
      "Fetch a single HTTP/HTTPS URL with GET and return the response status and a truncated body."

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "required" => ["url"],
      "properties" => %{
        "url" => %{"type" => "string", "format" => "uri"},
        "timeout_ms" => %{"type" => "integer", "minimum" => 100, "maximum" => 30_000}
      }
    }
  end

  @impl true
  def output_schema do
    %{
      "type" => "object",
      "required" => ["status", "body"],
      "properties" => %{
        "status" => %{"type" => "integer"},
        "body" => %{"type" => "string"},
        "truncated" => %{"type" => "boolean"},
        "url" => %{"type" => "string"}
      }
    }
  end

  @impl true
  def risk_level, do: :low

  @impl true
  def side_effects, do: ["Makes one outbound HTTP GET request to a public URL."]

  @impl true
  def failure_modes, do: ["tool_network_error", "tool_timeout", "tool_invalid_input"]

  @impl true
  def retry_policy do
    %{max_retries: 2, backoff_ms: 300, retry_on: ["tool_network_error", "tool_timeout"]}
  end

  @impl true
  def call(%{"url" => url} = input) when is_binary(url) do
    timeout = Map.get(input, "timeout_ms", @default_timeout_ms)

    with :ok <- check_scheme(url),
         {:ok, %{status: status, body: body}} <-
           Req.get(url, receive_timeout: timeout, max_redirects: 3) do
      {body_str, truncated?} = truncate(body)

      {:ok,
       %{
         "status" => status,
         "body" => body_str,
         "truncated" => truncated?,
         "url" => url
       }}
    else
      {:error, %{__exception__: true} = exc} -> {:error, Exception.message(exc)}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def call(_), do: {:error, "missing or invalid url"}

  defp check_scheme(url) do
    case URI.parse(url) do
      %URI{scheme: s} when s in ~w(http https) -> :ok
      _ -> {:error, "only http and https URLs are allowed"}
    end
  end

  defp truncate(body) when is_binary(body) do
    if byte_size(body) > @max_body_chars do
      {binary_part(body, 0, @max_body_chars), true}
    else
      {body, false}
    end
  end

  defp truncate(body) do
    encoded = body |> Jason.encode!() |> String.slice(0, @max_body_chars)
    truncated? = String.length(Jason.encode!(body)) > @max_body_chars
    {encoded, truncated?}
  end
end
