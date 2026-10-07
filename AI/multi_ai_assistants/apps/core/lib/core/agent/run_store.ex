defmodule Core.Agent.RunStore do
  @moduledoc "Durable checkpoints for a group-chat run."

  import Ecto.Query
  alias Core.Repo
  alias Core.Schema.AgentRun
  alias Core.Schema.Conversation

  def create(conversation_id, user_id, user_request) do
    if Repo.exists?(
         from(c in Conversation, where: c.id == ^conversation_id and c.user_id == ^user_id)
       ) do
      %AgentRun{}
      |> AgentRun.changeset(%{
        conversation_id: conversation_id,
        user_id: user_id,
        user_request: user_request
      })
      |> Repo.insert()
    else
      {:error, :conversation_not_owned}
    end
  end

  def get_owned(user_id, id) do
    from(r in AgentRun, where: r.user_id == ^user_id and r.id == ^id) |> Repo.one()
  end

  def open_for_conversation(user_id, conversation_id) do
    cutoff = DateTime.utc_now() |> DateTime.add(-300, :second)

    from(r in AgentRun,
      where:
        r.user_id == ^user_id and r.conversation_id == ^conversation_id and
          r.status == :running and r.updated_at < ^cutoff,
      order_by: [desc: r.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  def checkpoint(id, round, transcript) do
    case Repo.get(AgentRun, id) do
      %AgentRun{status: :running} = run ->
        run
        |> AgentRun.changeset(%{round: round, transcript: %{entries: transcript}})
        |> Repo.update()

      _ ->
        {:error, :run_not_running}
    end
  end

  def cancelled?(id) do
    case Repo.get(AgentRun, id) do
      %AgentRun{status: :cancelled} -> true
      _ -> false
    end
  end

  def cancel(user_id, id) do
    case get_owned(user_id, id) do
      %AgentRun{status: :running} = run ->
        run |> AgentRun.changeset(%{status: :cancelled}) |> Repo.update()

      _ ->
        {:error, :not_cancellable}
    end
  end

  def finish(id, answer) do
    case Repo.get(AgentRun, id) do
      %AgentRun{status: :running} = run ->
        run |> AgentRun.changeset(%{status: :completed, final_answer: answer}) |> Repo.update()

      _ ->
        {:error, :run_not_running}
    end
  end

  def fail(id, reason) do
    case Repo.get(AgentRun, id) do
      %AgentRun{status: :running} = run ->
        run |> AgentRun.changeset(%{status: :failed, error: inspect(reason)}) |> Repo.update()

      _ ->
        {:error, :run_not_running}
    end
  end

  def reserve_model_call(nil), do: :ok

  def reserve_model_call(id) do
    max_calls = Application.get_env(:core, :max_model_calls_per_run, 18)
    max_tokens = Application.get_env(:core, :max_tokens_per_run, 60_000)

    {count, _} =
      from(r in AgentRun,
        where:
          r.id == ^id and r.status == :running and r.model_calls < ^max_calls and
            r.tokens_used < ^max_tokens
      )
      |> Repo.update_all(inc: [model_calls: 1])

    if count == 1, do: :ok, else: {:error, :model_call_budget_exceeded}
  end

  def reserve_tool_call(nil), do: :ok

  def reserve_tool_call(id) do
    max_calls = Application.get_env(:core, :max_tool_calls_per_run, 24)

    {count, _} =
      from(r in AgentRun,
        where: r.id == ^id and r.status == :running and r.tool_calls < ^max_calls
      )
      |> Repo.update_all(inc: [tool_calls: 1])

    if count == 1, do: :ok, else: {:error, :tool_call_budget_exceeded}
  end

  def add_tokens(nil, _usage), do: :ok

  def add_tokens(id, %{"total_tokens" => tokens}) when is_integer(tokens) and tokens >= 0 do
    from(r in AgentRun, where: r.id == ^id)
    |> Repo.update_all(inc: [tokens_used: tokens])

    :telemetry.execute([:core, :agent, :tokens], %{total: tokens}, %{run_id: id})

    :ok
  end

  def add_tokens(_, _), do: :ok
end
