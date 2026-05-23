defmodule AgenticAiAgent.Skills do
  @moduledoc """
  Public API for the Skills index. Skills live as `priv/skills/<slug>/SKILL.md`
  files. At boot, only the frontmatter (name + description) is needed for
  matching; the body is injected into a sub-agent's system prompt when the
  skill is actually invoked via the `delegate` tool.
  """

  use GenServer

  alias AgenticAiAgent.Skills.Loader

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
