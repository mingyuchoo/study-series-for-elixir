# Elixir Todo

A local Todo List app built with Phoenix LiveView, SQLite, and a Tauri desktop shell.

## Web Development

Install the Elixir and Erlang versions in `.tool-versions`, plus Node.js/npm.
`mix setup` installs the locked npm dependencies and the configured asset tools.

```sh
mix setup
mix phx.server
```

Open <http://localhost:4000>.

## Desktop Development

The desktop shell uses Tauri. In development it opens the Phoenix dev server:

```sh
npm ci
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

Dependency versions are recorded in `mix.lock`, `package-lock.json`, and
`src-tauri/Cargo.lock`. Asset binary versions are configured in `config/config.exs`.
`phoenix_ecto` and `gettext` use pinned upstream commits because their latest Hex
releases do not include the Elixir 1.20 compiler compatibility fixes.
Rust transitive dependencies use the newest versions allowed by upstream constraints.
In particular, `crypto-common` pins `generic-array` to `0.14.7`, and
`proc-macro-crate` pins `toml_datetime` to `0.6.3` and `toml_edit` to `0.20.2`,
which also constrains the older `toml` dependency to `0.8.2`.
