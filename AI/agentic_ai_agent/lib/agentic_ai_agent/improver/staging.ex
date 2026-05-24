defmodule AgenticAiAgent.Improver.Staging do
  @moduledoc """
  Listener that finalises staging proposals when their eval finishes.

  Subscribes to the `"evals"` PubSub topic. On `{:eval, :finished, {:ok,
  eval_run}}`, looks up any improvement proposal whose `staging_slug`
  matches the eval's card slug AND `status == "staging"`. For each match,
  delegates to `Improver.record_staging_finish!/2` which computes the
  delta vs baseline and transitions the proposal to `staged_passed` or
  `staged_failed`.

  Why a separate GenServer (vs an inline Task in stage!): the eval can
  run for minutes; we don't want to block the caller, and we want a
  single, supervised process that reliably watches the topic even if the
  LiveView that triggered the staging disconnects.
  """

  use GenServer
  require Logger

  alias AgenticAiAgent.{Design, Eval, Improver, Repo}

  @topic Eval.pubsub_topic()

  # ----- Client -----

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  # ----- Server -----

  @impl true
  def init(:ok) do
    if Process.whereis(AgenticAiAgent.PubSub) do
      Phoenix.PubSub.subscribe(AgenticAiAgent.PubSub, @topic)
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info({:eval, :finished, {:ok, eval_run}}, state) do
    handle_eval_finish(eval_run)
    {:noreply, state}
  end

  def handle_info({:eval, :finished, {:error, reason}}, state) do
    Logger.debug("Staging: eval finished with error #{inspect(reason)}, no proposal update")
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  # ----- Internals -----

  defp handle_eval_finish(eval_run) do
    with %_{slug: slug} <- card_for(eval_run),
         proposals when proposals != [] <- Improver.list_pending_staging_for_slug(slug) do
      for p <- proposals do
        try do
          _ = Improver.record_staging_finish!(p, eval_run)
        rescue
          e ->
            Logger.warning("Staging: failed to finalise proposal #{p.id}: #{Exception.message(e)}")
        end
      end
    else
      _ -> :ok
    end
  rescue
    _ -> :ok
  end

  defp card_for(%{agentic_card_id: nil}), do: nil

  defp card_for(%{agentic_card_id: card_id}) do
    Repo.get(Design.AgenticCard, card_id)
  end

  defp card_for(_), do: nil
end
