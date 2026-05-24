defmodule AgenticAiAgent.Skills do
  @moduledoc """
  Public API for the Skills index. Skills live as `priv/skills/<slug>/SKILL.md`
  files. At boot, only the frontmatter (name + description) is needed for
  matching; the body is injected into a sub-agent's system prompt when the
  skill is actually invoked via the `delegate` tool.
  """

  use GenServer

  import Ecto.Query

  alias AgenticAiAgent.Repo
  alias AgenticAiAgent.Skills.{Loader, SkillVersion}

  # ----- Client -----

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Returns all loaded skills (slug, name, description, body, frontmatter)."
  def list, do: GenServer.call(__MODULE__, :list)

  @doc "Returns the skill with the given slug or nil."
  def get(slug), do: GenServer.call(__MODULE__, {:get, slug})

  @doc """
  Lists skill descriptors `{slug, name, description}` for inclusion in the
  agent's system prompt.
  """
  def descriptors do
    for s <- list(), do: %{slug: s.slug, name: s.name, description: s.description}
  end

  @doc "Re-read skill files from disk (development helper)."
  def reload, do: GenServer.call(__MODULE__, :reload)

  @doc """
  Absolute path to a skill's source markdown under `priv/skills/<slug>/SKILL.md`.
  Returns the path even if the file doesn't exist yet (callers should check
  existence via `File.exists?/1`).
  """
  @spec source_path(String.t()) :: String.t()
  def source_path(slug) when is_binary(slug) do
    Application.app_dir(:agentic_ai_agent, ["priv/skills", slug, "SKILL.md"])
  end

  @doc """
  Atomically write a skill's markdown source and reload the in-memory index.
  Validates by re-loading the file through `Loader.load_one/1`; on validation
  failure the previous file contents are restored.

  Returns `{:ok, skill}` or `{:error, reason}`.

  ## Options

    * `:reason` — optional short human note recorded on the version row.
  """
  @spec save_source(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def save_source(slug, body, opts \\ []) when is_binary(slug) and is_binary(body) do
    path = source_path(slug)
    backup = if File.exists?(path), do: File.read!(path), else: nil

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, body),
         skill when not is_nil(skill) <- Loader.load_one(path) do
      reload()
      _ = snapshot_skill_version(slug, body, Keyword.get(opts, :reason))
      {:ok, skill}
    else
      err ->
        case backup do
          nil -> _ = File.rm(path)
          body -> _ = File.write(path, body)
        end

        {:error, err}
    end
  end

  # ----- Skill versions -----

  @doc "All historical snapshots of a skill, newest first."
  @spec list_versions(String.t()) :: [SkillVersion.t()]
  def list_versions(slug) when is_binary(slug) do
    SkillVersion
    |> where(slug: ^slug)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  rescue
    _ -> []
  end

  @spec get_version!(binary()) :: SkillVersion.t()
  def get_version!(id), do: Repo.get!(SkillVersion, id)

  @doc """
  Roll the skill back to a historical version. Saves the historical body
  as a fresh write (which itself produces a new version row so the
  rollback is auditable).
  """
  @spec restore_version(SkillVersion.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def restore_version(%SkillVersion{} = v, opts \\ []) do
    reason = Keyword.get(opts, :reason, "restore version #{short_sha(v.sha)}")
    save_source(v.slug, v.body, reason: reason)
  end

  @doc "Short 12-char SHA for UI display."
  def short_sha(sha) when is_binary(sha), do: String.slice(sha, 0, 12)
  def short_sha(_), do: ""

  defp snapshot_skill_version(slug, body, reason) do
    sha = sha256(body)

    last_sha =
      SkillVersion
      |> where(slug: ^slug)
      |> order_by(desc: :inserted_at)
      |> limit(1)
      |> select([v], v.sha)
      |> Repo.one()

    if last_sha == sha do
      :ok
    else
      %SkillVersion{}
      |> SkillVersion.changeset(%{slug: slug, body: body, sha: sha, reason: reason})
      |> Repo.insert()
    end
  rescue
    _ -> :ok
  end

  defp sha256(body) when is_binary(body) do
    :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
  end

  # ----- Server -----

  @impl true
  def init(:ok) do
    {:ok, %{skills: Loader.load_all()}}
  end

  @impl true
  def handle_call(:list, _from, state), do: {:reply, state.skills, state}

  def handle_call({:get, slug}, _from, state) do
    {:reply, Enum.find(state.skills, &(&1.slug == slug)), state}
  end

  def handle_call(:reload, _from, _state) do
    skills = Loader.load_all()
    {:reply, length(skills), %{skills: skills}}
  end
end
