defmodule AgenticAiAgent.Tools.Registry do
  @moduledoc """
  Runtime registry of agent tools. Two shapes are supported:

    * **module entries** — a module implementing `AgenticAiAgent.Tool`. Used
      for built-in tools compiled into the application.
    * **dynamic entries** — a `%DynamicEntry{}` carrying the same metadata
      plus a dispatch function. Used by MCP-discovered tools and any other
      runtime-registered tool that isn't a static module.

  The registry validates input against each tool's JSON Schema, dispatches
  `call/1`, and mirrors every entry into the `tool_specs` table so the
  design layer can introspect available tools without booting OTP.
  """

  use GenServer
  require Logger

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Tools.{Specs, ToolSpec}

  @pubsub_topic "tools"

  @doc "PubSub topic used for broadcasting tool lifecycle events."
  def pubsub_topic, do: @pubsub_topic

  defmodule DynamicEntry do
    @moduledoc """
    A non-module tool entry. `dispatch` is `(input :: map) -> {:ok, map} | {:error, term}`.
    Optional fields (precheck/side_effects/failure_modes/retry_policy) carry
    the same metadata as the `Tool` behaviour's optional callbacks.
    """
    defstruct [
      :name,
      :description,
      :input_schema,
      :output_schema,
      :risk_level,
      :dispatch,
      precheck: nil,
      side_effects: [],
      failure_modes: [],
      retry_policy: %{},
      source: nil
    ]
  end

  @builtin [
    AgenticAiAgent.Tools.Calculator,
    AgenticAiAgent.Tools.HttpFetch,
    AgenticAiAgent.Tools.WebSearch,
    AgenticAiAgent.Tools.MemorySearch,
    AgenticAiAgent.Tools.MemoryStore,
    AgenticAiAgent.Tools.PythonExec,
    AgenticAiAgent.Tools.RepoPatch,
    AgenticAiAgent.Tools.Delegate
  ]

  # ----- Client API -----

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns `{:ok, entry}` if a tool with that name is registered."
  def lookup(name), do: GenServer.call(__MODULE__, {:lookup, name})

  @doc "List `[{name, entry}, ...]` of all registered tools."
  def list, do: GenServer.call(__MODULE__, :list)

  @doc "Returns true if the tool exists and is not disabled by its ToolSpec row."
  def enabled?(name), do: GenServer.call(__MODULE__, {:enabled?, name})

  @doc """
  Apply a user-supplied edit to the tool's ToolSpec row (risk_level, enabled,
  retry_policy) and refresh the cached override. Broadcasts `{:tool, :updated,
  name}` on the `\"tools\"` PubSub topic.
  """
  def update_spec(name, attrs) when is_binary(name),
    do: GenServer.call(__MODULE__, {:update_spec, name, attrs})

  @doc "List tool descriptors suitable for an LLM tool-use payload. Disabled tools are filtered out."
  def descriptors do
    for {name, entry} <- list(), enabled?(name) do
      %{
        "name" => name,
        "description" => description_of(entry),
        "input_schema" => input_schema_of(entry),
        "risk_level" => Atom.to_string(risk_level(name))
      }
    end
  end

  @doc "Register a new tool — accepts a module or a `%DynamicEntry{}`."
  def register(module_or_entry), do: GenServer.call(__MODULE__, {:register, module_or_entry})

  @doc "Unregister a tool by name. No-op if it doesn't exist."
  def unregister(name), do: GenServer.call(__MODULE__, {:unregister, name})

  @doc """
  Validate `input` against the tool's input schema and dispatch.
  Returns `{:ok, output}` / `{:error, {:invalid_input, errors}}` / `{:error, reason}`.
  """
  def call(name, input) do
    case lookup(name) do
      :error ->
        {:error, {:unknown_tool, name}}

      {:ok, entry} ->
        if enabled?(name),
          do: validate_and_dispatch(entry, input),
          else: {:error, {:tool_disabled, name}}
    end
  end

  @doc """
  Effective risk level (atom) of a tool by name — DB override if present,
  otherwise the code-defined default. Returns `:unknown` if not registered.
  """
  def risk_level(name), do: GenServer.call(__MODULE__, {:risk_level, name})

  @doc """
  Full metadata map for a tool — used by the catalog UI. Reflects any
  DB-stored overrides (risk_level, enabled, retry_policy). Returns `nil`
  for unknown tools.
  """
  def metadata(name), do: GenServer.call(__MODULE__, {:metadata, name})

  # ----- Server -----

  @impl true
  def init(_opts) do
    tools =
      for m <- @builtin, into: %{} do
        sync_spec_for(m)
        {m.name(), m}
      end

    {:ok, %{tools: tools, specs: load_specs_map()}}
  end

  @impl true
  def handle_call(:list, _from, state),
    do: {:reply, Enum.sort(Map.to_list(state.tools)), state}

  def handle_call({:lookup, name}, _from, state),
    do: {:reply, Map.fetch(state.tools, name), state}

  def handle_call({:enabled?, name}, _from, state) do
    {:reply, effective_enabled?(state, name), state}
  end

  def handle_call({:risk_level, name}, _from, state) do
    {:reply, effective_risk_level(state, name), state}
  end

  def handle_call({:metadata, name}, _from, state) do
    reply =
      case Map.fetch(state.tools, name) do
        {:ok, entry} ->
          spec = Map.get(state.specs, name)

          %{
            name: name_of(entry),
            description: description_of(entry),
            input_schema: input_schema_of(entry),
            output_schema: output_schema_of(entry),
            risk_level: effective_risk_level(state, name),
            enabled: effective_enabled?(state, name),
            side_effects: side_effects_of(entry),
            failure_modes: failure_modes_of(entry),
            retry_policy: (spec && spec.retry_policy) || retry_policy_of(entry),
            source: source_of(entry),
            spec_id: spec && spec.id
          }

        :error ->
          nil
      end

    {:reply, reply, state}
  end

  def handle_call({:update_spec, name, attrs}, _from, state) do
    spec = Specs.get_spec_by_name(name) || Map.get(state.specs, name)

    case spec do
      nil ->
        {:reply, {:error, :unknown_tool}, state}

      %ToolSpec{} = spec ->
        case Specs.update(spec, attrs) do
          {:ok, updated} ->
            Phoenix.PubSub.broadcast(
              AgenticAiAgent.PubSub,
              @pubsub_topic,
              {:tool, :updated, updated.name}
            )

            {:reply, {:ok, updated},
             %{state | specs: Map.put(state.specs, updated.name, updated)}}

          {:error, _} = err ->
            {:reply, err, state}
        end
    end
  end

  def handle_call({:register, module_or_entry}, _from, state) do
    name = name_of(module_or_entry)
    sync_spec_for(module_or_entry)

    spec = Specs.get_spec_by_name(name)
    specs = if spec, do: Map.put(state.specs, name, spec), else: state.specs

    {:reply, :ok, %{state | tools: Map.put(state.tools, name, module_or_entry), specs: specs}}
  end

  def handle_call({:unregister, name}, _from, state) do
    {:reply, :ok,
     %{state | tools: Map.delete(state.tools, name), specs: Map.delete(state.specs, name)}}
  end

  defp load_specs_map do
    for spec <- Specs.list_specs(), into: %{}, do: {spec.name, spec}
  rescue
    _ -> %{}
  end

  defp effective_enabled?(state, name) do
    case Map.fetch(state.tools, name) do
      :error ->
        false

      {:ok, _} ->
        case Map.get(state.specs, name) do
          %ToolSpec{enabled: enabled} -> enabled
          nil -> true
        end
    end
  end

  defp effective_risk_level(state, name) do
    case Map.fetch(state.tools, name) do
      :error ->
        :unknown

      {:ok, entry} ->
        case Map.get(state.specs, name) do
          %ToolSpec{risk_level: r} when is_binary(r) and r != "" ->
            String.to_existing_atom(r)

          _ ->
            risk_level_atom(entry)
        end
    end
  end

  # ----- Dispatch helpers -----

  defp validate_and_dispatch(entry, input) do
    schema = ExJsonSchema.Schema.resolve(input_schema_of(entry))

    case ExJsonSchema.Validator.validate(schema, input) do
      :ok -> safe_dispatch(entry, input)
      {:error, errors} -> {:error, {:invalid_input, format_errors(errors)}}
    end
  rescue
    e -> {:error, {:schema_error, Exception.message(e)}}
  end

  defp safe_dispatch(module, input) when is_atom(module),
    do: rescue_call(fn -> module.call(input) end)

  defp safe_dispatch(%DynamicEntry{dispatch: dispatch}, input),
    do: rescue_call(fn -> dispatch.(input) end)

  defp rescue_call(fun) do
    fun.()
  rescue
    e -> {:error, {:tool_crash, Exception.message(e)}}
  catch
    kind, reason -> {:error, {:tool_throw, {kind, reason}}}
  end

  defp format_errors(errors) when is_list(errors) do
    for err <- errors do
      case err do
        {msg, path} when is_binary(msg) and is_binary(path) -> %{"path" => path, "message" => msg}
        other -> %{"message" => inspect(other)}
      end
    end
  end

  # ----- Metadata accessors (work for both module and dynamic entries) -----

  defp name_of(module) when is_atom(module), do: module.name()
  defp name_of(%DynamicEntry{name: n}), do: n

  defp description_of(module) when is_atom(module), do: module.description()
  defp description_of(%DynamicEntry{description: d}), do: d

  defp input_schema_of(module) when is_atom(module), do: module.input_schema()
  defp input_schema_of(%DynamicEntry{input_schema: s}), do: s

  defp output_schema_of(module) when is_atom(module), do: module.output_schema()
  defp output_schema_of(%DynamicEntry{output_schema: s}), do: s

  defp risk_level_atom(module) when is_atom(module), do: module.risk_level()
  defp risk_level_atom(%DynamicEntry{risk_level: r}), do: r

  defp risk_level_string(entry), do: entry |> risk_level_atom() |> Atom.to_string()

  defp side_effects_of(module) when is_atom(module) do
    if function_exported?(module, :side_effects, 0), do: module.side_effects(), else: []
  end

  defp side_effects_of(%DynamicEntry{side_effects: list}) when is_list(list), do: list
  defp side_effects_of(_), do: []

  defp failure_modes_of(module) when is_atom(module) do
    if function_exported?(module, :failure_modes, 0), do: module.failure_modes(), else: []
  end

  defp failure_modes_of(%DynamicEntry{failure_modes: list}) when is_list(list), do: list
  defp failure_modes_of(_), do: []

  defp retry_policy_of(module) when is_atom(module) do
    if function_exported?(module, :retry_policy, 0), do: module.retry_policy(), else: %{}
  end

  defp retry_policy_of(%DynamicEntry{retry_policy: map}) when is_map(map), do: map
  defp retry_policy_of(_), do: %{}

  defp source_of(%DynamicEntry{source: s}), do: s
  defp source_of(_), do: nil

  defp run_precheck(module, input) when is_atom(module) do
    if function_exported?(module, :precheck, 1), do: module.precheck(input), else: :ok
  end

  defp run_precheck(%DynamicEntry{precheck: f}, input) when is_function(f, 1), do: f.(input)
  defp run_precheck(_, _), do: :ok

  # ----- DB sync -----

  defp sync_spec_for(entry) do
    attrs = %{
      name: name_of(entry),
      purpose: description_of(entry),
      input_schema: input_schema_of(entry),
      output_schema: output_schema_of(entry),
      risk_level: risk_level_string(entry),
      side_effects: side_effects_of(entry) |> Enum.join("; "),
      failure_modes: failure_modes_of(entry),
      retry_policy: stringify(retry_policy_of(entry)),
      enabled: true
    }

    case Repo.get_by(ToolSpec, name: attrs.name) do
      nil -> %ToolSpec{} |> ToolSpec.changeset(attrs) |> Repo.insert!()
      existing -> existing |> ToolSpec.changeset(attrs) |> Repo.update!()
    end
  rescue
    e ->
      Logger.warning("tool spec sync failed: #{Exception.message(e)}")
      :ok
  end

  # Serialize retry_policy keys as strings (works for both atom-keyed and
  # string-keyed maps).
  defp stringify(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {to_string(k), v}
    end)
  end

  defp stringify(_), do: %{}

  @doc """
  Dispatch `name` with `input` using the tool's own precheck + retry policy.
  Same return contract as `call/2`. Each retry attempt re-validates against
  the schema (cheap and keeps semantics simple).
  """
  def call_with_policy(name, input) do
    case lookup(name) do
      :error ->
        {:error, {:unknown_tool, name}}

      {:ok, entry} ->
        case run_precheck(entry, input) do
          :ok -> dispatch_with_retry(entry, input)
          {:error, reason} -> {:error, {:precheck_failed, reason}}
        end
    end
  end

  defp dispatch_with_retry(entry, input) do
    policy = retry_policy_of(entry)
    max = Map.get(policy, :max_retries) || Map.get(policy, "max_retries") || 0
    backoff = Map.get(policy, :backoff_ms) || Map.get(policy, "backoff_ms") || 250

    retry_on =
      (Map.get(policy, :retry_on) || Map.get(policy, "retry_on") || [])
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    attempt(entry, input, 0, max, backoff, retry_on)
  end

  defp attempt(entry, input, n, max, backoff, retry_on) do
    case validate_and_dispatch(entry, input) do
      {:ok, _} = ok ->
        ok

      {:error, reason} = err when n < max ->
        if transient?(reason, retry_on) do
          :timer.sleep(backoff * (n + 1))
          attempt(entry, input, n + 1, max, backoff, retry_on)
        else
          err
        end

      {:error, _} = err ->
        err
    end
  end

  # Use the Failures.Detector to classify; only retry on slugs the tool listed.
  defp transient?(reason, retry_on) do
    case AgenticAiAgent.Failures.Detector.classify_tool_error(reason) do
      {:ok, slug, _} -> MapSet.member?(retry_on, slug)
      :unknown -> false
    end
  end
end
