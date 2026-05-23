defmodule AgenticAiAgent.Memory.Cleaner do
  @moduledoc """
  Periodic sweeper that deletes memories whose TTL has elapsed. Runs every
  `:sweep_interval_ms` (default 1 hour) and on demand via `sweep_now/0`.

  Only rows with `deletion_rule == "ttl"` AND a non-nil `retention_days`
  are eligible. Everything else is left untouched.

  Disable in tests / specific environments via:

      config :agentic_ai_agent, AgenticAiAgent.Memory.Cleaner, enabled: false
  """

  use GenServer
  require Logger

  alias AgenticAiAgent.Memory

  @default_interval :timer.hours(1)

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
    interval = Keyword.get(cfg, :sweep_interval_ms, @default_interval)
    enabled = Keyword.get(cfg, :enabled, true)

    state = %{interval: interval, enabled: enabled}
    if enabled, do: schedule_next(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    do_sweep()
    schedule_next(state)
    {:noreply, state}
  end

  @impl true
  def handle_call(:sweep_now, _from, state) do
    n = do_sweep()
    {:reply, n, state}
  end

  defp do_sweep do
    n = Memory.sweep_expired()
    if n > 0, do: Logger.info("Memory.Cleaner: removed #{n} expired memories")

    :telemetry.execute(
      [:memory, :sweep],
      %{deleted: n},
      %{}
    )

    n
  rescue
    e ->
      Logger.warning("Memory.Cleaner: sweep failed — #{Exception.message(e)}")
      0
  end

  defp schedule_next(%{interval: interval}) do
    Process.send_after(self(), :sweep, interval)
    :ok
  end
end
