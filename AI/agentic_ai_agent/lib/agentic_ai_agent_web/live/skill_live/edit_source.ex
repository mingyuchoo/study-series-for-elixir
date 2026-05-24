defmodule AgenticAiAgentWeb.SkillLive.EditSource do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Skills

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    path = Skills.source_path(slug)

    {body, mtime, existed?} =
      case File.read(path) do
        {:ok, body} -> {body, mtime_of(path), true}
        _ -> {template(slug), nil, false}
      end

    {:ok,
     socket
     |> assign(:slug, slug)
     |> assign(:path, path)
     |> assign(:original_mtime, mtime)
     |> assign(:body, body)
     |> assign(:existed?, existed?)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("validate", %{"body" => body}, socket) do
    {:noreply, assign(socket, :body, body)}
  end

  def handle_event("save", %{"body" => body}, socket) do
    cond do
      mtime_changed?(socket) ->
        {:noreply,
         assign(socket, :error,
           gettext("The file on disk changed since you opened it. Reload and reapply your edits.")
         )}

      true ->
        case Skills.save_source(socket.assigns.slug, body) do
          {:ok, _skill} ->
            {:noreply,
             socket
             |> put_flash(:info, gettext("Saved %{path}.", path: relativize(socket.assigns.path)))
             |> push_navigate(to: ~p"/skills")}

          {:error, nil} ->
            {:noreply,
             assign(socket, :error,
               gettext("The new content could not be parsed as a SKILL.md (frontmatter missing or invalid).")
             )}

          {:error, reason} ->
            {:noreply, assign(socket, :error, gettext("Save failed: %{r}", r: inspect(reason)))}
        end
    end
  end

  # ----- Helpers -----

  defp mtime_of(path) do
    case File.stat(path) do
      {:ok, %{mtime: m}} -> m
      _ -> nil
    end
  end

  defp mtime_changed?(socket) do
    socket.assigns.original_mtime != nil and
      mtime_of(socket.assigns.path) != socket.assigns.original_mtime
  end

  defp relativize(absolute) when is_binary(absolute) do
    case String.split(absolute, "/priv/", parts: 2) do
      [_, rest] -> "priv/" <> rest
      _ -> absolute
    end
  end

  defp template(slug) do
    """
    ---
    name: #{slug}
    description: (one-line description of when to use this skill)
    ---

    # #{slug}

    Step 1. ...
    """
  end

  # ----- Render -----

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="mx-auto max-w-3xl space-y-4">
        <header class="flex items-baseline justify-between">
          <div>
            <h1 class="text-2xl font-semibold">{gettext("Edit skill source")}</h1>
            <p class="font-mono text-xs opacity-60">
              {relativize(@path)}
              <span :if={!@existed?} class="ml-2 rounded bg-amber-100 dark:bg-amber-900/40 px-1.5 py-0.5 text-[10px] text-amber-800 dark:text-amber-200">
                {gettext("new file")}
              </span>
            </p>
          </div>
          <.link navigate={~p"/skills"} class="text-xs opacity-70 hover:underline">
            ← {gettext("Back to skills")}
          </.link>
        </header>

        <p class="text-xs opacity-70">
          {gettext("The skill is YAML frontmatter (name, description, tools_used) followed by Markdown body. Saving writes the file and reloads the in-memory index.")}
        </p>

        <div :if={@error} class="rounded border border-red-400 dark:border-red-600 bg-red-50 dark:bg-red-950/40 p-2 text-xs text-red-700 dark:text-red-200">
          {@error}
        </div>

        <form phx-submit="save" phx-change="validate">
          <textarea
            name="body"
            rows="28"
            class="w-full rounded border px-3 py-2 font-mono text-xs"
            phx-debounce="500"
          >{@body}</textarea>

          <div class="mt-3 flex items-center gap-3">
            <button type="submit" class="rounded bg-black px-4 py-2 text-sm text-white">
              {gettext("Save")}
            </button>
            <.link navigate={~p"/skills"} class="text-sm opacity-70 hover:underline">
              {gettext("Cancel")}
            </.link>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
