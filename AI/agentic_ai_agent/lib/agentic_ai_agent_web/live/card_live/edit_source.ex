defmodule AgenticAiAgentWeb.CardLive.EditSource do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Design

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    card = Design.get_card!(id)
    path = Design.card_source_path(card.slug)

    {body, mtime} =
      case path && File.read(path) do
        {:ok, body} ->
          {body, mtime_of(path)}

        _ ->
          {empty_yaml_template(card.slug, card.name), nil}
      end

    {:ok,
     socket
     |> assign(:card, card)
     |> assign(:path, path)
     |> assign(:original_mtime, mtime)
     |> assign(:body, body)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("save", %{"body" => body}, socket) do
    cond do
      mtime_changed?(socket) ->
        {:noreply,
         assign(socket, :error,
           gettext("The file on disk changed since you opened it. Reload the page and reapply your edits.")
         )}

      true ->
        do_save(socket, body)
    end
  end

  def handle_event("validate", %{"body" => body}, socket) do
    {:noreply, assign(socket, :body, body)}
  end

  # ----- Save -----

  defp do_save(socket, body) do
    case Design.save_card_source(socket.assigns.card.slug, body) do
      {:ok, %{card: card, path: path}} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Saved %{path} and re-synced the card.", path: relativize(path)))
         |> push_navigate(to: ~p"/cards/#{card.id}")}

      {:error, {:error, %YamlElixir.ParsingError{message: msg, line: line}}} ->
        {:noreply,
         assign(socket, :error, gettext("YAML parse error on line %{line}: %{msg}", line: line, msg: msg))}

      {:error, {:error, %Ecto.Changeset{} = cs}} ->
        {:noreply,
         assign(socket, :error,
           gettext("Validation failed: %{e}",
             e: cs |> errors_to_string() |> String.slice(0, 240)
           )
         )}

      {:error, other} ->
        {:noreply, assign(socket, :error, gettext("Save failed: %{r}", r: inspect(other)))}
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
    case socket.assigns.path do
      nil -> false
      path -> mtime_of(path) != socket.assigns.original_mtime and socket.assigns.original_mtime != nil
    end
  end

  defp relativize(absolute) when is_binary(absolute) do
    case String.split(absolute, "/priv/", parts: 2) do
      [_, rest] -> "priv/" <> rest
      _ -> absolute
    end
  end

  defp errors_to_string(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.map_join("; ", fn {k, msgs} -> "#{k}: #{Enum.join(msgs, ", ")}" end)
  end

  defp empty_yaml_template(slug, name) do
    """
    slug: #{slug}
    name: #{name}
    role: |
      (describe the agent's role)
    goal: |
      (what is the agent trying to achieve?)
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
            <h1 class="text-2xl font-semibold">{gettext("Edit card source")}</h1>
            <p class="font-mono text-xs opacity-60">
              {if @path, do: relativize(@path), else: gettext("(new file)")}
            </p>
          </div>
          <.link navigate={~p"/cards/#{@card.id}"} class="text-xs opacity-70 hover:underline">
            ← {gettext("Back to detail")}
          </.link>
        </header>

        <p class="text-xs opacity-70">
          {gettext("The card's behavior is driven by this YAML. Saving writes the file, re-parses it, and upserts the DB. Validation errors leave the previous file contents untouched.")}
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
            <button type="submit" class="px-6 py-2 text-sm font-medium" style="background:#141413;color:#F3F0EE;border-radius:20px;letter-spacing:-0.02em;">
              {gettext("Save")}
            </button>
            <.link navigate={~p"/cards/#{@card.id}"} class="text-sm opacity-70 hover:underline">
              {gettext("Cancel")}
            </.link>
          </div>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
