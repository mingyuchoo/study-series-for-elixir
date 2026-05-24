defmodule AgenticAiAgentWeb.SkillLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Skills

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :skills, Skills.list())}
  end

  @impl true
  def handle_event("reload", _params, socket) do
    count = Skills.reload()

    {:noreply,
     socket
     |> put_flash(:info, gettext("Reloaded %{n} skill(s) from priv/skills/.", n: count))
     |> assign(:skills, Skills.list())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="flex items-baseline justify-between gap-3">
          <div>
            <div class="eyebrow mb-2">{gettext("Skills")}</div>
            <h1 class="text-2xl font-semibold">{gettext("Skills")}</h1>
            <p class="text-sm opacity-70">
              {gettext("Skills live as Markdown files under priv/skills/<slug>/SKILL.md with optional YAML frontmatter. Only the description is consulted for matching; the body is injected into a sub-agent's system prompt via the delegate tool.")}
            </p>
          </div>
          <button
            phx-click="reload"
            type="button"
            class="shrink-0 whitespace-nowrap rounded border px-3 py-1 text-xs hover:bg-base-200"
          >
            {gettext("Reload from files")}
          </button>
        </header>

        <div :if={@skills == []} class="rounded border border-dashed p-6 text-center opacity-70">
          {gettext("No skills loaded. Add a file at priv/skills/<slug>/SKILL.md.")}
        </div>

        <article :for={s <- @skills} class="space-y-3 rounded-lg border p-4">
          <header class="flex items-baseline justify-between">
            <h2 class="text-lg font-semibold">{s.name}</h2>
            <code class="font-mono text-xs opacity-60">{s.slug}</code>
          </header>

          <p :if={s[:path]} class="font-mono text-[11px] opacity-50">
            {gettext("source:")} {relativize(s.path)}
            <.link
              navigate={~p"/skills/#{s.slug}/edit-source"}
              class="ml-2 rounded border px-1.5 py-0 text-[10px] opacity-80 hover:bg-base-200"
            >
              {gettext("Edit")}
            </.link>
            <.link
              navigate={~p"/skills/#{s.slug}/history"}
              class="ml-1 rounded border px-1.5 py-0 text-[10px] opacity-80 hover:bg-base-200"
            >
              {gettext("History")}
            </.link>
          </p>

          <p class="text-sm opacity-80">{s.description}</p>

          <div :if={s.frontmatter["tools_used"]} class="text-xs opacity-70">
            <span class="font-semibold uppercase tracking-wide">{gettext("tools_used:")}</span>
            <code class="font-mono">{Enum.join(s.frontmatter["tools_used"], ", ")}</code>
          </div>

          <details>
            <summary class="cursor-pointer text-xs font-semibold uppercase tracking-wide opacity-70">
              {gettext("body")}
            </summary>
            <pre class="mt-2 overflow-x-auto whitespace-pre-wrap rounded bg-base-200 p-3 text-xs">{s.body}</pre>
          </details>

          <details :if={s.frontmatter != %{}}>
            <summary class="cursor-pointer text-xs font-semibold uppercase tracking-wide opacity-70">
              {gettext("frontmatter")}
            </summary>
            <pre class="mt-2 overflow-x-auto rounded bg-base-200 p-3 text-xs">{Jason.encode!(s.frontmatter, pretty: true)}</pre>
          </details>
        </article>
      </div>
    </Layouts.app>
    """
  end

  defp relativize(nil), do: ""

  defp relativize(absolute) when is_binary(absolute) do
    case String.split(absolute, "/priv/", parts: 2) do
      [_, rest] -> "priv/" <> rest
      _ -> absolute
    end
  end
end
