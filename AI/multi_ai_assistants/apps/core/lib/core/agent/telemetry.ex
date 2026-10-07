defmodule Core.Agent.Telemetry do
  @moduledoc "Agent operation telemetry. Run IDs correlate model, tool, and orchestration events."

  def measure(operation, metadata, callback) when is_atom(operation) do
    started = System.monotonic_time()

    try do
      result = callback.()
      emit(operation, started, Map.put(metadata, :outcome, outcome(result)))
      result
    rescue
      exception ->
        emit(operation, started, Map.put(metadata, :outcome, :exception))
        reraise exception, __STACKTRACE__
    end
  end

  def emit_count(operation, metadata) do
    :telemetry.execute([:core, :agent, operation], %{count: 1}, metadata)
  end

  defp emit(operation, started, metadata) do
    :telemetry.execute(
      [:core, :agent, operation],
      %{count: 1, duration: System.monotonic_time() - started},
      metadata
    )
  end

  defp outcome({:ok, %Req.Response{status: status}}) when status >= 400, do: :error
  defp outcome({:ok, _}), do: :ok
  defp outcome({:ok, _, _}), do: :ok
  defp outcome({:error, _}), do: :error
  defp outcome(_), do: :ok
end
