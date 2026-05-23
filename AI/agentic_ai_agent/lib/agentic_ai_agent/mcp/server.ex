defmodule AgenticAiAgent.MCP.Server do
  @moduledoc """
  Ecto schema for a configured MCP server.

  Persistent counterpart of the runtime config that used to live in
  `Application.get_env(:agentic_ai_agent, :mcp_servers, ...)`. Rows in this
  table are the authoritative source of MCP server configuration; on app
  boot every `enabled` row is launched under `AgenticAiAgent.MCP.ClientSupervisor`.

  Fields:

    * `name` — unique server identifier; tools register as `mcp__<name>__<tool>`
    * `command` — executable to spawn (must be on PATH)
    * `args` — list of strings passed to the executable. Stored as a JSON map
      `%{"list" => [...]}` because SQLite's `:map` column does not preserve
      top-level list ordering; helpers below wrap/unwrap.
    * `env` — extra environment variables for the child process
    * `risk_level` — `low | medium | high | critical`; inherited by every tool
      discovered from this server
    * `enabled` — when false, the row exists but is not launched
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @risk_levels ~w(low medium high critical)

  schema "mcp_servers" do
    field :name, :string
    field :command, :string
    field :args, :map, default: %{"list" => []}
    field :env, :map, default: %{}
    field :risk_level, :string, default: "medium"
    field :enabled, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(server, attrs) do
    attrs = attrs |> normalize_args_attr() |> normalize_env_attr()

    server
    |> cast(attrs, [:name, :command, :args, :env, :risk_level, :enabled])
    |> validate_required([:name, :command])
    |> validate_format(:name, ~r/\A[a-z0-9][a-z0-9_-]*\z/,
      message: "lowercase letters, digits, _ or -, must start with letter/digit"
    )
    |> validate_length(:name, max: 64)
    |> validate_inclusion(:risk_level, @risk_levels)
    |> unique_constraint(:name)
  end

  @doc "Return args as a plain list of strings (the form stores `%{\"list\" => [...]}`)."
  @spec args_list(t()) :: [String.t()]
  def args_list(%__MODULE__{args: %{"list" => list}}) when is_list(list), do: list
  def args_list(_), do: []

  @doc "Return env as a map of binary→binary."
  @spec env_map(t()) :: %{String.t() => String.t()}
  def env_map(%__MODULE__{env: env}) when is_map(env), do: env
  def env_map(_), do: %{}

  @type t :: %__MODULE__{}

  # Accept :args as a list, a whitespace-separated string, or the already-wrapped
  # `%{"list" => [...]}` form. Normalize to the wrapped form *before* cast/3 so
  # SQLite's :map column accepts it.
  defp normalize_args_attr(attrs) when is_map(attrs) do
    {key, raw} = take_either(attrs, ["args", :args])

    case raw do
      :missing ->
        attrs

      list when is_list(list) ->
        Map.put(attrs, key, %{"list" => Enum.map(list, &to_string/1)})

      %{"list" => list} when is_list(list) ->
        Map.put(attrs, key, %{"list" => Enum.map(list, &to_string/1)})

      str when is_binary(str) ->
        list = str |> String.split(~r/\s+/, trim: true)
        Map.put(attrs, key, %{"list" => list})

      _ ->
        # Leave whatever it is; cast/3 will surface a type error.
        attrs
    end
  end

  defp normalize_args_attr(attrs), do: attrs

  defp normalize_env_attr(attrs) when is_map(attrs) do
    {key, raw} = take_either(attrs, ["env", :env])

    case raw do
      :missing ->
        attrs

      env when is_map(env) ->
        env =
          env
          |> Enum.reject(fn {k, _} -> to_string(k) == "" end)
          |> Map.new(fn {k, v} -> {to_string(k), to_string(v)} end)

        Map.put(attrs, key, env)

      _ ->
        attrs
    end
  end

  defp normalize_env_attr(attrs), do: attrs

  defp take_either(attrs, [first | rest]) do
    if Map.has_key?(attrs, first) do
      {first, Map.get(attrs, first)}
    else
      case rest do
        [] -> {first, :missing}
        _ -> take_either(attrs, rest)
      end
    end
  end
end
