defmodule AgenticAiAgentWeb.MCPLive.Form do
  use AgenticAiAgentWeb, :live_view

  alias AgenticAiAgent.MCP.{Server, Servers}

  @impl true
  def mount(params, _session, socket) do
    {server, page_title} =
      case socket.assigns.live_action do
        :new -> {%Server{}, gettext("New MCP server")}
        :edit -> {Servers.get!(params["id"]), gettext("Edit MCP server")}
      end

    changeset = Servers.change(server)

    {:ok,
     socket
     |> assign(:server, server)
     |> assign(:page_title, page_title)
     |> assign(:form, to_form(changeset))
     |> assign(:transport, server.transport || "stdio")
     |> assign(:args_text, args_to_text(server))
     |> assign(:env_text, env_to_text(server))
     |> assign(:headers_text, headers_to_text(server))}
  end

  @impl true
  def handle_event("validate", %{"server" => params}, socket) do
    params = normalize_params(params)

    changeset =
      socket.assigns.server
      |> Servers.change(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:transport, params["transport"] || socket.assigns.transport)
     |> assign(:args_text, params["__args_text"] || socket.assigns.args_text)
     |> assign(:env_text, params["__env_text"] || socket.assigns.env_text)
     |> assign(:headers_text, params["__headers_text"] || socket.assigns.headers_text)}
  end

  def handle_event("save", %{"server" => params}, socket) do
    params = normalize_params(params)

    save(socket.assigns.live_action, socket.assigns.server, params, socket)
  end

  # ----- Save -----

  defp save(:new, _server, params, socket) do
    case Servers.create(params) do
      {:ok, _server} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("MCP server created."))
         |> push_navigate(to: ~p"/mcp")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(:edit, server, params, socket) do
    case Servers.update(server, params) do
      {:ok, _server} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("MCP server updated."))
         |> push_navigate(to: ~p"/mcp")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # ----- Helpers -----

  defp normalize_params(params) do
    args = params["args_text"] |> to_string() |> parse_args()
    env = params["env_text"] |> to_string() |> parse_env()
    headers = params["headers_text"] |> to_string() |> parse_env()

    params
    |> Map.put("args", args)
    |> Map.put("env", env)
    |> Map.put("headers", headers)
    |> Map.put("__args_text", params["args_text"])
    |> Map.put("__env_text", params["env_text"])
    |> Map.put("__headers_text", params["headers_text"])
    |> Map.drop(["args_text", "env_text", "headers_text"])
  end

  # Args parsing: one arg per line (whitespace-trimmed). Allow blank lines.
  defp parse_args(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Env parsing: KEY=value per line. Blank lines and comments (#) are ignored.
  defp parse_env(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn line -> line == "" or String.starts_with?(line, "#") end)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, "=", parts: 2) do
        [k, v] -> Map.put(acc, String.trim(k), String.trim(v))
        _ -> acc
      end
    end)
  end

  defp args_to_text(%Server{} = server),
    do: server |> Server.args_list() |> Enum.join("\n")

  defp env_to_text(%Server{} = server) do
    server
    |> Server.env_map()
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map_join("\n", fn {k, v} -> "#{k}=#{v}" end)
  end

  defp headers_to_text(%Server{} = server) do
    server
    |> Server.headers_map()
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map_join("\n", fn {k, v} -> "#{k}=#{v}" end)
  end

  # ----- Render -----

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} locale={@locale}>
      <div class="mx-auto max-w-2xl space-y-6">
        <header class="flex items-baseline justify-between">
          <h1 class="text-2xl font-semibold">{@page_title}</h1>
          <.link navigate={~p"/mcp"} class="text-xs opacity-70 hover:underline">
            ← {gettext("Back")}
          </.link>
        </header>

        <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
          <.input field={@form[:name]} type="text" label={gettext("Name")}
            placeholder="filesystem"
            phx-debounce="200" />

          <p class="-mt-3 text-[11px] opacity-60">
            {gettext("Tool calls will be exposed as mcp__<name>__<tool>. Lowercase, dashes or underscores.")}
          </p>

          <.input field={@form[:transport]} type="select" label={gettext("Transport")}
            options={[{gettext("stdio (local child process)"), "stdio"}, {gettext("http_sse (remote URL)"), "http_sse"}]} />

          <!-- stdio fields -->
          <div :if={@transport == "stdio"} class="space-y-4">
            <.input field={@form[:command]} type="text" label={gettext("Command")}
              placeholder="npx"
              phx-debounce="200" />

            <div>
              <label class="mb-1 block text-sm font-semibold">{gettext("Args")} <span class="opacity-50">({gettext("one per line")})</span></label>
              <textarea
                name="server[args_text]"
                rows="4"
                class="w-full rounded border px-2 py-1 font-mono text-xs"
                phx-debounce="200"
              >{@args_text}</textarea>
            </div>

            <div>
              <label class="mb-1 block text-sm font-semibold">{gettext("Env")} <span class="opacity-50">(KEY=value, {gettext("one per line")})</span></label>
              <textarea
                name="server[env_text]"
                rows="3"
                class="w-full rounded border px-2 py-1 font-mono text-xs"
                phx-debounce="200"
              >{@env_text}</textarea>
            </div>
          </div>

          <!-- http_sse fields -->
          <div :if={@transport == "http_sse"} class="space-y-4">
            <.input field={@form[:url]} type="text" label={gettext("SSE URL")}
              placeholder="https://server.example.com/sse"
              phx-debounce="200" />
            <p class="-mt-3 text-[11px] opacity-60">
              {gettext("HTTPS recommended. The first SSE event carries the POST endpoint for JSON-RPC requests.")}
            </p>

            <div>
              <label class="mb-1 block text-sm font-semibold">{gettext("Headers")} <span class="opacity-50">(KEY=value, {gettext("one per line")})</span></label>
              <textarea
                name="server[headers_text]"
                rows="3"
                class="w-full rounded border px-2 py-1 font-mono text-xs"
                phx-debounce="200"
              >{@headers_text}</textarea>
              <p class="mt-1 text-[11px] opacity-60">
                {gettext("e.g. Authorization=Bearer xxx. Sent on the SSE GET and every POST.")}
              </p>
            </div>
          </div>

          <.input field={@form[:risk_level]} type="select" label={gettext("Risk level")}
            options={[{"low", "low"}, {"medium", "medium"}, {"high", "high"}, {"critical", "critical"}]} />

          <.input field={@form[:enabled]} type="checkbox" label={gettext("Enabled")} />

          <div class="flex items-center gap-3 pt-2">
            <button type="submit" class="rounded bg-black px-4 py-2 text-sm text-white">
              {gettext("Save")}
            </button>
            <.link navigate={~p"/mcp"} class="text-sm opacity-70 hover:underline">
              {gettext("Cancel")}
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
