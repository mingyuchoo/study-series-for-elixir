defmodule AgenticAiAgent.LLM.Pricing do
  @moduledoc """
  Per-deployment token pricing. Prices are stored as **USD per 1,000,000
  tokens** (matching the way Azure/OpenAI publish them). The runtime
  converts `usage` → micro-USD per call and accumulates onto the run row.

  Pricing storage is intentionally lightweight: an in-memory defaults map
  plus a single config override hook. Update the defaults from the
  provider's pricing page when you onboard a new model.

      # config/runtime.exs
      config :agentic_ai_agent, AgenticAiAgent.LLM.Pricing,
        prices: %{
          "gpt-5.3-chat" => %{input: 1.25, output: 5.00},
          "my-custom-deployment" => %{input: 0.5, output: 1.5}
        }

  Unknown deployments return `nil` — cost tracking is then skipped for
  those calls (rather than logging a wrong number).
  """

  # Defaults sourced from Azure OpenAI pricing pages (subject to drift —
  # always confirm in config). USD per 1,000,000 tokens.
  @defaults %{
    # Chat / reasoning models
    "gpt-4o" => %{input: 2.50, output: 10.00},
    "gpt-4o-mini" => %{input: 0.15, output: 0.60},
    "gpt-4.1" => %{input: 2.00, output: 8.00},
    "gpt-4.1-mini" => %{input: 0.40, output: 1.60},
    "gpt-4.1-nano" => %{input: 0.10, output: 0.40},
    "o3-mini" => %{input: 1.10, output: 4.40},
    "o4-mini" => %{input: 1.10, output: 4.40},
    # Placeholder for the user's deployment in this scaffold.
    # Override via config for the real number.
    "gpt-5.3-chat" => %{input: 1.25, output: 5.00},

    # Embeddings
    "text-embedding-3-small" => %{input: 0.02, output: 0.0},
    "text-embedding-3-large" => %{input: 0.13, output: 0.0}
  }

  @doc """
  Get pricing for a model. Returns `%{input: usd_per_1m, output: usd_per_1m}`
  or `nil`.
  """
  def for_model(nil), do: nil

  def for_model(name) when is_binary(name) do
    case lookup(name) do
      nil -> normalised_lookup(name)
      hit -> hit
    end
  end

  defp lookup(name) do
    overrides = Application.get_env(:agentic_ai_agent, __MODULE__, [])[:prices] || %{}
    Map.get(overrides, name) || Map.get(@defaults, name)
  end

  # Azure deployments often include a date suffix (e.g. "gpt-4o-mini-2024-07-18").
  # Strip trailing -YYYY-MM-DD if the exact name didn't match.
  defp normalised_lookup(name) do
    case Regex.run(~r/^(.+?)(?:-\d{4}-\d{2}-\d{2})$/, name) do
      [_, base] -> Map.get(@defaults, base)
      _ -> nil
    end
  end

  @doc """
  Compute the cost in **micro-USD** (1 USD = 1_000_000 µ$) for one call.

  Accepts both string-keyed and atom-keyed usage maps. Returns `nil` if the
  model isn't priced or the usage is unusable.
  """
  def cost_micro_usd(model, usage) do
    case for_model(model) do
      %{input: in_rate, output: out_rate} ->
        p = get_int(usage, "prompt_tokens") || get_int(usage, :prompt_tokens) || 0
        c = get_int(usage, "completion_tokens") || get_int(usage, :completion_tokens) || 0

        if p == 0 and c == 0 do
          nil
        else
          round(p * in_rate + c * out_rate)
        end

      _ ->
        nil
    end
  end

  defp get_int(map, key) when is_map(map) do
    case Map.get(map, key) do
      n when is_integer(n) -> n
      _ -> nil
    end
  end

  defp get_int(_, _), do: nil

  # ----- Formatting helpers (used by views) -----

  @doc "Convert micro-USD to USD as a float."
  def micro_to_usd(nil), do: nil
  def micro_to_usd(n) when is_integer(n), do: n / 1_000_000

  @doc """
  Human-readable price string. Picks a sensible precision based on
  magnitude so 5 µ$ doesn't render as $0.00.
  """
  def format(nil), do: "—"
  def format(0), do: "$0.000000"

  def format(n) when is_integer(n) do
    usd = n / 1_000_000

    cond do
      usd >= 1.0 -> "$" <> :erlang.float_to_binary(usd, decimals: 2)
      usd >= 0.01 -> "$" <> :erlang.float_to_binary(usd, decimals: 4)
      true -> "$" <> :erlang.float_to_binary(usd, decimals: 6)
    end
  end
end
