defmodule AgenticAiAgent.Tools.Specs do
  @moduledoc """
  Read + edit helpers for the `tool_specs` table.

  Each row mirrors the code-defined metadata of one tool module (or
  dynamic MCP entry). The Registry auto-inserts rows on boot; this module
  exposes the *editable* subset (`risk_level`, `enabled`, `retry_policy`)
  to the UI.

  Create/delete are intentionally not exposed — specs are derived from
  registered tools, so adding a row that has no corresponding code would
  be meaningless.
  """

  import Ecto.Query

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Tools.ToolSpec

  @editable ~w(risk_level enabled retry_policy)a

  @spec list_specs() :: [ToolSpec.t()]
  def list_specs do
    ToolSpec
    |> order_by([s], asc: s.name)
    |> Repo.all()
  rescue
    _ -> []
  end

  @spec get_spec!(binary()) :: ToolSpec.t()
  def get_spec!(id), do: Repo.get!(ToolSpec, id)

  @spec get_spec_by_name(String.t()) :: ToolSpec.t() | nil
  def get_spec_by_name(name), do: Repo.get_by(ToolSpec, name: name)

  @spec change(ToolSpec.t(), map()) :: Ecto.Changeset.t()
  def change(%ToolSpec{} = spec, attrs \\ %{}), do: editable_changeset(spec, attrs)

  @doc """
  Update only the editable fields. Form-supplied `retry_policy` may be a
  JSON string from a textarea; if so we parse before casting.
  """
  @spec update(ToolSpec.t(), map()) :: {:ok, ToolSpec.t()} | {:error, Ecto.Changeset.t()}
  def update(%ToolSpec{} = spec, attrs) do
    spec
    |> editable_changeset(attrs)
    |> Repo.update()
  end

  @type t :: ToolSpec.t()

  defp editable_changeset(%ToolSpec{} = spec, attrs) do
    import Ecto.Changeset

    attrs = normalize_retry_policy(attrs)

    spec
    |> cast(attrs, @editable)
    |> validate_inclusion(:risk_level, ~w(low medium high critical))
  end

  defp normalize_retry_policy(attrs) when is_map(attrs) do
    {key, raw} =
      cond do
        Map.has_key?(attrs, "retry_policy") -> {"retry_policy", attrs["retry_policy"]}
        Map.has_key?(attrs, :retry_policy) -> {:retry_policy, attrs[:retry_policy]}
        true -> {nil, :missing}
      end

    case raw do
      :missing ->
        attrs

      str when is_binary(str) ->
        case Jason.decode(String.trim(str)) do
          {:ok, map} when is_map(map) -> Map.put(attrs, key, map)
          # On parse error, leave the raw string; cast/3 will surface the
          # type mismatch as a validation error.
          _ -> attrs
        end

      _ ->
        attrs
    end
  end

  defp normalize_retry_policy(attrs), do: attrs
end
