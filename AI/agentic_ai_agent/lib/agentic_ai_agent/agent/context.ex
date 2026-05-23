defmodule AgenticAiAgent.Agent.Context do
  @moduledoc """
  Per-turn context that gets transiently prepended to the LLM input. Implements
  `eval.md` §9 (Context Model):

      user_intent / session_history / environment_state
      retrieved_documents / tool_results / constraints / unresolved_questions

  In this phase the only **dynamic** section is `retrieved_documents` — the
  runtime auto-RAGs the long-term memory store on every turn. The other six
  sections are filled in passively from existing state (conversation, card,
  step trace) so the model's system message is shaped uniformly.

  Retrieval honours the card's `reasoning_policy.retrieval`:

      reasoning_policy:
        retrieval:
          enabled: true       # default true if memory backend is reachable
          k: 5                # default 5
          min_score: 0.0      # default 0.0 (no filter)
          query_source: last_user   # `last_user` | `concat_last_n` (future)

  Embedding-adapter failures degrade silently — the run continues without
  retrieved context and `retrieved_documents` is `[]`.
  """

  alias AgenticAiAgent.{Conversation, Memory}

  @type retrieved :: {score :: float(), memory :: map()}

  defstruct user_intent: nil,
            environment: %{},
            retrieved: [],
            constraints: nil,
            unresolved_questions: [],
            embedding_meta: nil

  @default_retrieval %{
    "enabled" => true,
    "k" => 5,
    "min_score" => 0.0,
    "query_source" => "last_user"
  }

  @doc """
  Build a context object for the current turn. Reads the conversation's
  last user message, runs a similarity search if enabled, and returns
  `{:ok, %Context{}}`. Never raises.
  """
  @spec build(GenServer.server() | nil, map() | nil) :: {:ok, %__MODULE__{}}
  def build(conversation, card) do
    cfg = retrieval_config(card)
    intent = pick_query(conversation, cfg)

    {retrieved, meta} =
      cond do
        cfg["enabled"] != true -> {[], nil}
        is_nil(intent) -> {[], nil}
        true -> safe_search(intent, cfg)
      end

    {:ok,
     %__MODULE__{
       user_intent: intent,
       environment: %{
         "time" => DateTime.utc_now() |> DateTime.to_iso8601(),
         "card" => card && card.slug
       },
       retrieved: retrieved,
       constraints: card && card.scope,
       embedding_meta: meta
     }}
  end

  @doc """
  Returns a system message map suitable to prepend to the chat payload,
  or `nil` if there is nothing useful to inject.
  """
  @spec to_system_message(%__MODULE__{}) :: map() | nil
  def to_system_message(%__MODULE__{retrieved: []}), do: nil

  def to_system_message(%__MODULE__{retrieved: retrieved}) do
    body =
      retrieved
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {{score, m}, i} ->
        "#{i}. (score=#{Float.round(score, 3)}) [#{m.kind}/#{m.source || "—"}] #{m.content}"
      end)

    %{
      "role" => "system",
      "content" =>
        "[RETRIEVED CONTEXT]\n" <>
          "The following long-term memories may be relevant to the user's latest message. " <>
          "Use them only if directly applicable; they may be outdated or off-topic.\n\n" <>
          body
    }
  end

  @doc """
  Trace-friendly payload for `Traces.add_step!/4`. Includes the query and
  a shallow projection of the matches (id/score/kind/source/content
  preview) so the run timeline stays scannable.
  """
  @spec to_step_payload(%__MODULE__{}) :: map()
  def to_step_payload(%__MODULE__{} = ctx) do
    %{
      "query" => ctx.user_intent,
      "matches" =>
        for {score, m} <- ctx.retrieved do
          %{
            "id" => m.id,
            "score" => Float.round(score, 4),
            "kind" => m.kind,
            "source" => m.source,
            "content_preview" => preview(m.content)
          }
        end,
      "match_count" => length(ctx.retrieved)
    }
  end

  # ----- Helpers -----

  defp retrieval_config(nil), do: @default_retrieval

  defp retrieval_config(card) do
    case card.reasoning_policy do
      %{"retrieval" => map} when is_map(map) -> Map.merge(@default_retrieval, map)
      _ -> @default_retrieval
    end
  end

  defp pick_query(nil, _cfg), do: nil

  defp pick_query(conversation, _cfg) do
    conversation
    |> Conversation.turns()
    |> Enum.reverse()
    |> Enum.find_value(nil, fn
      %{"role" => "user", "content" => c} when is_binary(c) and c != "" -> c
      _ -> nil
    end)
  end

  defp safe_search(query, cfg) do
    case Memory.search_with_meta(query, k: cfg["k"], min_score: cfg["min_score"]) do
      {:ok, results, meta} -> {results, meta}
      {:error, _reason} -> {[], nil}
    end
  rescue
    _ -> {[], nil}
  catch
    _, _ -> {[], nil}
  end

  defp preview(nil), do: ""

  defp preview(text) when is_binary(text) do
    if String.length(text) > 160, do: String.slice(text, 0, 160) <> "…", else: text
  end
end
