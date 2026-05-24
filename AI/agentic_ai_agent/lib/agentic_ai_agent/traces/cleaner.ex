defmodule AgenticAiAgent.Traces.Cleaner do
  @moduledoc """
  Periodic sweeper that deletes runs older than `:retention_days`. Runs every
  `:sweep_interval_ms` (default 6 hours) and on demand via `sweep_now/0`.

  **Disabled by default** — opt in by setting `retention_days` to a positive
  integer in `config/runtime.exs`:

      config :agentic_ai_agent, AgenticAiAgent.Traces.Cleaner,
        enabled: true,
        retention_days: 30,
        sweep_interval_ms: :timer.hours(6)

  If `enabled` is true but `retention_days` is nil/0/negative, the cleaner
  stays in the supervision tree but every sweep is a no-op. This makes the
  GenServer safe to start unconditionally and toggled purely by config.

  Cascade behaviour matches `Traces.delete_runs_older_than/1`:

    * `steps` / `tool_calls` / `approvals` / `failure_occurrences` are
      deleted via FK cascade
    * `eval_cases.run_id` is nilified (eval scores survive)
    * child runs' `parent_run_id` is nilified (sub-agent history survives)
  """

  use GenServer
  require Logger

  alias AgenticAiAgent.Traces

  @default_interval :timer.hours(6)

  # ----- Client -----

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Force an immediate sweep. Returns the number of rows deleted."
  def sweep_now, do: GenServer.call(__MODULE__, :sweep_now)

  # ----- Server -----

  @impl true
  def init(_opts) do
    cfg = Application.get_env(:agentic_ai_agent, __MODULE__, [])

    state = %{
      enabled: Keyword.get(cfg, :enabled, false),
      retention_days: Keyword.get(cfg, :retention_days),
      interval: Keyword.get(cfg, :sweep_interval_ms, @default_interval)
    }

    if state.enabled, do: schedule_next(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    do_sweep(state)
    schedule_next(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:sweep_now, _from, state) do
    {:reply, do_sweep(state), state}
  end

  defp do_sweep(%{retention_days: days}) when is_integer(days) and days > 0 do
    n = Traces.delete_runs_older_than(days)
    if n > 0, do: Logger.info("Traces.Cleaner: removed #{n} run(s) older than #{days} day(s)")

    :telemetry.execute([:traces, :sweep], %{deleted: n}, %{retention_days: days})

    n
  rescue
    e ->
      Logger.warning("Traces.Cleaner: sweep failed — #{Exception.message(e)}")
      0
  end

  defp do_sweep(_state), do: 0

  defp schedule_next(%{interval: interval}) do
    Process.send_after(self(), :sweep, interval)
    :ok
  end
end
