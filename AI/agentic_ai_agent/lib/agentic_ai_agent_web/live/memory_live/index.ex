defmodule AgenticAiAgentWeb.MemoryLive.Index do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.Memory
  alias AgenticAiAgent.Memory.Cleaner

  @impl true
  def mount(_params, _session, socket) do
    {:ok, refresh(socket)}
  end

  defp refresh(socket) do
    socket
    |> assign(:memories, Memory.list())
    |> assign(:count, Memory.count())
    |> assign(:by_sensitivity, Memory.count_by_sensitivity())
    |> assign(:search_form, to_form(%{"query" => ""}))
    |> assign(:store_form, to_form(%{"content" => "", "kind" => "semantic", "source" => "user"}))
    |> assign_new(:search_results, fn -> nil end)
    |> assign_new(:error, fn -> nil end)
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    query = String.trim(query)

    cond do
      query == "" ->
        {:noreply, assign(socket, :search_results, nil)}

      true ->
        case Memory.search(query, k: 10) do
          {:ok, results} ->
            {:noreply,
             socket
             |> assign(:search_results, {query, results})
             |> assign(:error, nil)}

          {:error, reason} ->
            {:noreply, assign(socket, :error, format_error(reason))}
        end
    end
  end

  def handle_event("store", %{"content" => content} = params, socket) do
    content = String.trim(content)

    if content == "" do
      {:noreply, socket}
    else
      opts =
        [
          kind: Map.get(params, "kind", "semantic"),
          source: Map.get(params, "source", "user"),
          sensitivity: Map.get(params, "sensitivity", "internal"),
          update_rule: Map.get(params, "update_rule", "append_only"),
          deletion_rule: Map.get(params, "deletion_rule", "manual")
        ]
        |> maybe_put_int(:retention_days, Map.get(params, "retention_days"))

      case Memory.remember(content, opts) do
        {:ok, _mem} ->
          {:noreply, refresh(socket) |> assign(:error, nil)}

        {:error, reason} ->
          {:noreply, assign(socket, :error, format_error(reason))}
      end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Memory.get!(id) |> Memory.delete!()
    {:noreply, refresh(socket)}
  end

  def handle_event("sweep", _params, socket) do
    n = Cleaner.sweep_now()
    msg = gettext("Sweep removed %{n} expired memories.", n: n)
    {:noreply, refresh(socket) |> put_flash(:info, msg)}
  end

  defp maybe_put_int(opts, _key, value) when value in [nil, ""], do: opts

  defp maybe_put_int(opts, key, value) do
    case Integer.parse(to_string(value)) do
      {n, _} when n > 0 -> Keyword.put(opts, key, n)
      _ -> opts
    end
  end

  defp format_error({:missing_config, key}),
    do: gettext("Embeddings adapter not configured (missing %{key}). Set AZURE_OPENAI_EMBEDDINGS_DEPLOYMENT.", key: to_string(key))

  defp format_error({:http_error, status, body}),
    do: gettext("Embeddings HTTP %{status}: %{body}", status: status, body: inspect(body) |> String.slice(0, 300))

  defp format_error({:transport_error, msg}), do: gettext("Network error: %{msg}", msg: inspect(msg))
  defp format_error(other), do: inspect(other)

  defp sensitivity_color("public"), do: "bg-blue-100 dark:bg-blue-900/40 text-blue-800 dark:text-blue-200"
  defp sensitivity_color("internal"), do: "bg-base-200 opacity-70"
  defp sensitivity_color("private"), do: "bg-amber-100 dark:bg-amber-900/40 text-amber-800 dark:text-amber-200"
  defp sensitivity_color("secret"), do: "bg-red-100 dark:bg-red-900/40 text-red-800 dark:text-red-200"
  defp sensitivity_color(_), do: "bg-base-200"

  defp expiry_label(%{retention_days: d, inserted_at: t}) when is_integer(d) do
    expires =
      t
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.add(d * 86_400, :second)

    diff_sec = DateTime.diff(expires, DateTime.utc_now(), :second)

    cond do
      diff_sec <= 0 -> " · #{gettext("expired")}"
      diff_sec < 86_400 -> " · #{gettext("expires in <1d")}"
      true -> " · #{gettext("expires in")} #{div(diff_sec, 86_400)}#{gettext("d")}"
    end
  end

  defp expiry_label(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="space-y-6">
        <header class="flex items-baseline justify-between gap-3">
          <div>
            <div class="eyebrow mb-2">{gettext("Memories")}</div>
            <h1 class="text-2xl font-semibold">{gettext("Memories")}</h1>
            <p class="text-sm opacity-70">
              {gettext("Long-term memory store. Embedding-based semantic search runs in-process over the SQLite-backed corpus.")}
            </p>
            <p class="mt-1 flex flex-wrap items-center gap-1 font-mono text-[10px] opacity-70">
              <span :for={s <- ~w(public internal private secret)} class={["rounded px-2 py-0.5", sensitivity_color(s)]}>
                {s}: {Map.get(@by_sensitivity, s, 0)}
              </span>
            </p>
          </div>
          <div class="flex flex-col items-end gap-2">
            <span class="font-mono text-xs opacity-60">{@count} {gettext("rows")}</span>
            <button
              phx-click="sweep"
              type="button"
              class="rounded border px-3 py-1 text-xs hover:bg-base-200"
            >
              {gettext("Sweep expired")}
            </button>
          </div>
        </header>

        <div :if={@error} class="rounded border border-red-400 dark:border-red-600 bg-red-50 dark:bg-red-950/40 p-2 text-xs text-red-700 dark:text-red-200">
          {@error}
        </div>

        <section class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide opacity-70">{gettext("Search")}</h2>
          <.form for={@search_form} phx-submit="search" class="flex gap-2">
            <input
              name="query"
              value={@search_form[:query].value}
              placeholder={gettext("Semantic query...")}
              autocomplete="off"
              class="flex-1 rounded border px-3 py-2 text-sm"
            />
            <button
              type="submit"
              class="px-6 py-2 text-sm font-medium"
              style="background:#141413;color:#F3F0EE;border-radius:20px;letter-spacing:-0.02em;"
            >
              {gettext("Search")}
            </button>
          </.form>

          <div :if={@search_results} class="space-y-2">
            <p class="font-mono text-xs opacity-60">
              {gettext("query:")} {elem(@search_results, 0)} ·
              {length(elem(@search_results, 1))} {gettext("results")}
            </p>
            <ul class="space-y-2">
              <li
                :for={{score, m} <- elem(@search_results, 1)}
                class="rounded border border-emerald-300 dark:border-emerald-700 bg-emerald-50 dark:bg-emerald-950/40 p-3 text-sm"
              >
                <div class="mb-1 flex items-center justify-between font-mono text-xs opacity-70">
                  <span>{gettext("score:")} {Float.round(score, 4)}</span>
                  <span>{m.kind} · {m.source || "—"}</span>
                </div>
                <p class="whitespace-pre-wrap">{m.content}</p>
              </li>
            </ul>
          </div>
        </section>

        <section class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide opacity-70">{gettext("Add")}</h2>
          <.form for={@store_form} phx-submit="store" class="space-y-2">
            <textarea
              name="content"
              placeholder={gettext("A fact to remember...")}
              class="w-full rounded border px-3 py-2 text-sm"
              rows="3"
            >{@store_form[:content].value}</textarea>
            <div class="flex flex-wrap items-center gap-2">
              <select name="kind" class="rounded border px-2 py-1 text-xs">
                <option :for={k <- AgenticAiAgent.Memory.Memory.kinds()} value={k} selected={k == @store_form[:kind].value}>
                  {k}
                </option>
              </select>
              <input
                name="source"
                value={@store_form[:source].value}
                placeholder={gettext("source")}
                class="rounded border px-2 py-1 text-xs"
              />
              <select name="sensitivity" class="rounded border px-2 py-1 text-xs" title={gettext("sensitivity")}>
                <option :for={s <- AgenticAiAgent.Memory.Memory.sensitivities()} value={s} selected={s == "internal"}>
                  {s}
                </option>
              </select>
              <select name="update_rule" class="rounded border px-2 py-1 text-xs" title={gettext("update_rule")}>
                <option value="append_only" selected>append_only</option>
                <option value="overwrite_by_source">overwrite_by_source</option>
                <option value="overwrite_by_id">overwrite_by_id</option>
              </select>
              <select name="deletion_rule" class="rounded border px-2 py-1 text-xs" title={gettext("deletion_rule")}>
                <option value="manual" selected>manual</option>
                <option value="ttl">ttl</option>
                <option value="on_request">on_request</option>
              </select>
              <input
                name="retention_days"
                type="number"
                min="1"
                placeholder={gettext("days")}
                class="w-20 rounded border px-2 py-1 text-xs"
                title={gettext("retention_days (only used with deletion_rule=ttl)")}
              />
              <button
                type="submit"
                class="ml-auto px-5 py-1.5 text-xs font-medium"
                style="background:#141413;color:#F3F0EE;border-radius:20px;letter-spacing:-0.02em;"
              >
                {gettext("Remember")}
              </button>
            </div>
          </.form>
        </section>

        <section class="space-y-2">
          <h2 class="text-sm font-semibold uppercase tracking-wide opacity-70">
            {gettext("All memories")}
          </h2>
          <ul :if={@memories != []} class="space-y-2">
            <li :for={m <- @memories} class="rounded border p-3 text-sm">
              <div class="mb-1 flex items-center justify-between gap-2">
                <div class="flex items-center gap-2 font-mono text-xs opacity-70">
                  <span>{m.kind}</span>
                  <span>· {m.source || "—"}</span>
                  <span class={["rounded px-2 py-0.5 text-[10px] uppercase", sensitivity_color(m.sensitivity)]}>
                    {m.sensitivity || "internal"}
                  </span>
                  <span :if={m.confidence && m.confidence < 1.0} class="opacity-70">
                    {gettext("conf:")} {Float.round(m.confidence, 2)}
                  </span>
                </div>
                <button
                  phx-click="delete"
                  phx-value-id={m.id}
                  data-confirm={gettext("Delete this memory?")}
                  class="rounded border px-2 py-0.5 text-[10px] text-red-700 dark:text-red-200 hover:bg-red-50 dark:bg-red-950/40"
                >
                  {gettext("delete")}
                </button>
              </div>
              <p class="whitespace-pre-wrap">{m.content}</p>
              <p class="mt-1 font-mono text-[10px] opacity-60">
                {gettext("update_rule:")} {m.update_rule || "append_only"} ·
                {gettext("deletion_rule:")} {m.deletion_rule || "manual"}
                <span :if={m.retention_days}>
                  · {gettext("retention:")} {m.retention_days}{gettext("d")}
                  <span :if={m.deletion_rule == "ttl"} class="opacity-70">
                    {expiry_label(m)}
                  </span>
                </span>
              </p>
              <p class="mt-1 font-mono text-[10px] opacity-50">
                {gettext("model:")} {m.embedding_model || "?"} · {gettext("accessed:")} {m.access_count}×
              </p>
            </li>
          </ul>
          <div :if={@memories == []} class="rounded border border-dashed p-6 text-center text-sm opacity-60">
            {gettext("No memories yet.")}
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
