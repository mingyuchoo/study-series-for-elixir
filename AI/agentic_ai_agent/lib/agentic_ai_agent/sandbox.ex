defmodule AgenticAiAgent.Sandbox do
  @moduledoc """
  Isolated code execution layer. The brain (LLM) and the hands (sandbox)
  are decoupled — the agent calls `run_python/2` and receives a structured
  `%Result{}`. If the sandbox crashes, the runtime is unaffected and can
  retry by calling again (a fresh sandbox is provisioned each time).

  Strategy selection:

    * If `docker` is on PATH and reachable, a one-shot container is run with
      `--network=none --memory=512m --cpus=1.0`. Each call is a fresh container.
    * Otherwise the host's `python3` (or `python`) is invoked directly via
      `Port`. This is convenient for dev but provides only timeout isolation,
      not OS-level sandboxing.

  Override via config:

      config :agentic_ai_agent, AgenticAiAgent.Sandbox,
        strategy: :docker | :native | :auto,
        image: "python:3.12-slim",
        default_timeout_ms: 10_000,
        memory: "512m",
        cpus: "1.0"
  """

  defmodule Result do
    @moduledoc false
    defstruct exit_status: nil,
              stdout: "",
              stderr: "",
              timed_out?: false,
              strategy: nil,
              duration_ms: 0
  end

  @default_timeout_ms 10_000
  @default_image "python:3.12-slim"
  @max_output_bytes 16_384

  @doc """
  Execute `code` with the active strategy. `opts`:

    * `:timeout_ms` — hard kill timeout (default 10_000)
    * `:stdin` — bytes piped to the code's stdin
  """
  @spec run_python(String.t(), keyword()) :: Result.t()
  def run_python(code, opts \\ []) when is_binary(code) do
    strategy = active_strategy()
    timeout = Keyword.get(opts, :timeout_ms, default_timeout())
    stdin = Keyword.get(opts, :stdin)

    started = System.monotonic_time(:millisecond)

    result =
      case strategy do
        :docker -> run_docker(code, timeout, stdin)
        :native -> run_native(code, timeout, stdin)
      end

    %{result | strategy: strategy, duration_ms: System.monotonic_time(:millisecond) - started}
  end

  # ----- Strategy selection -----

  defp active_strategy do
    case Keyword.get(cfg(), :strategy, :auto) do
      :docker -> :docker
      :native -> :native
      :auto -> if docker_available?(), do: :docker, else: :native
    end
  end

  def docker_available? do
    case System.find_executable("docker") do
      nil ->
        false

      _ ->
        case System.cmd("docker", ["info"], stderr_to_stdout: true) do
          {_, 0} -> true
          _ -> false
        end
    end
  end

  def native_python_available? do
    System.find_executable("python3") != nil or System.find_executable("python") != nil
  end

  defp cfg, do: Application.get_env(:agentic_ai_agent, __MODULE__, [])
  defp default_timeout, do: Keyword.get(cfg(), :default_timeout_ms, @default_timeout_ms)

  # ----- Native (host) python -----

  defp run_native(code, timeout, stdin) do
    case System.find_executable("python3") || System.find_executable("python") do
      nil ->
        %Result{exit_status: -1, stderr: "no python3 interpreter on PATH"}

      python ->
        run_port(python, ["-u", "-c", code], timeout, stdin)
    end
  end

  # ----- Docker one-shot -----

  defp run_docker(code, timeout, stdin) do
    image = Keyword.get(cfg(), :image, @default_image)
    memory = Keyword.get(cfg(), :memory, "512m")
    cpus = Keyword.get(cfg(), :cpus, "1.0")

    docker_args =
      [
        "run",
        "--rm",
        "--network=none",
        "--memory=#{memory}",
        "--cpus=#{cpus}",
        "--pids-limit=64",
        image,
        "python3",
        "-u",
        "-c",
        code
      ]

    case System.find_executable("docker") do
      nil ->
        %Result{exit_status: -1, stderr: "docker disappeared from PATH"}

      docker ->
        run_port(docker, docker_args, timeout, stdin)
    end
  end

  # ----- Generic Port driver -----

  defp run_port(executable, args, timeout, stdin) do
    opts = [:binary, :exit_status, :stderr_to_stdout, :use_stdio, args: args]
    port = Port.open({:spawn_executable, executable}, opts)

    if is_binary(stdin) do
      send(port, {self(), {:command, stdin}})
      send(port, {self(), :close})
    end

    collect(port, "", timeout)
  end

  defp collect(port, acc, timeout) do
    receive do
      {^port, {:data, chunk}} ->
        acc = acc <> chunk

        if byte_size(acc) > @max_output_bytes do
          close_port(port)
          %Result{exit_status: -1, stdout: trim_output(acc), stderr: "output exceeded #{@max_output_bytes}B"}
        else
          collect(port, acc, timeout)
        end

      {^port, {:exit_status, status}} ->
        %Result{exit_status: status, stdout: trim_output(acc)}
    after
      timeout ->
        close_port(port)
        %Result{exit_status: -1, stdout: trim_output(acc), stderr: "timed out after #{timeout}ms", timed_out?: true}
    end
  end

  defp trim_output(bin) when byte_size(bin) > @max_output_bytes,
    do: binary_part(bin, 0, @max_output_bytes) <> "\n...[truncated]"

  defp trim_output(bin), do: bin

  defp close_port(port) do
    try do
      Port.close(port)
    catch
      :error, _ -> :ok
    end
  end
end
