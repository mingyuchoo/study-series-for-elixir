# Elixir Todo

A local Todo List app built with Phoenix LiveView, SQLite, and a Tauri desktop shell.

## Web Development

```sh
mix setup
mix phx.server
```

Open <http://localhost:4000>.

## Desktop Development

The desktop shell uses Tauri. In development it opens the Phoenix dev server:

```sh
npm install
npm run desktop:dev
```

Production desktop builds bundle a Phoenix release and run it on `127.0.0.1:4017`.
Desktop mode stores SQLite data and the generated Phoenix secret under the OS app-data
directory, or under `ELIXIR_GUI_TODO_HOME` when that environment variable is set.

```sh
scripts/release.sh
```

On Linux this produces `.deb` and `.rpm` installers. On macOS it produces a `.dmg`.
On Windows, run `scripts/release.ps1` to produce an `.msi` installer.

Platform builds should be verified on the target OS because Tauri installers and WebView
runtime behavior differ between Linux, macOS, and Windows.
