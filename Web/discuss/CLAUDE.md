# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Setup & Development

```bash
# Full setup (install deps + create + migrate + seed DB)
mix setup

# Start development server (with IEx shell)
iex -S mix phx.server

# Start server only
mix phx.server
```

### Database

```bash
mix ecto.create          # Create the database
mix ecto.migrate         # Run migrations
mix ecto.reset           # Drop and recreate with migrations + seeds
mix run apps/discuss/priv/repo/seeds.exs  # Run seeds only
```

### Testing

```bash
mix test                                        # Run all tests (auto-creates and migrates test DB)
mix test apps/discuss/test/                     # Test a specific app
mix test apps/discuss_web/test/                 # Test the web app
mix test apps/discuss/test/discuss/topics_test.exs  # Run a single test file
```

### Assets

```bash
mix assets.build    # Build CSS + JS (dev)
mix assets.deploy   # Minify and digest for production
```

### Makefile shortcuts

```bash
make all      # clean → deps.get → ecto.create → ecto.migrate → iex -S mix phx.server
make release  # Docker build + run
```

## Architecture

This is an **Elixir umbrella application** using Phoenix 1.7 with Bandit as the HTTP adapter.

### App dependency chain

```
discuss_web → discuss_auth → discuss
```

### Apps

- **`apps/discuss`** — Core domain layer
  - `Discuss.Repo` — Ecto repository (PostgreSQL)
  - `Discuss.Topics` context — CRUD for topics (`Discuss.Topics.Topic` schema)
  - `Discuss.Admin` context — Admin user schema (separate from auth users)
  - `Discuss.Mailer` — Swoosh-based email

- **`apps/discuss_auth`** — Authentication layer
  - `DiscussAuth.Accounts` context — User registration, login, session management
  - `DiscussAuth.Accounts.User` — User schema with Pbkdf2 password hashing
  - `DiscussAuth.Accounts.UserToken` — 60-day session tokens stored in DB

- **`apps/discuss_web`** — Phoenix web layer
  - `DiscussWeb.Router` — Three route groups: public, unauthenticated-only (register/login), authenticated-only (topics CRUD)
  - `DiscussWeb.UserAuth` — Plug for session management (`fetch_current_user`, `require_authenticated_user`, `redirect_if_user_is_authenticated`)
  - Controllers: `TopicController`, `UserRegistrationController`, `UserSessionController`, `PageController`
  - Assets: Tailwind CSS + esbuild, Heroicons via CSS masks

### Key design notes

- **All Ecto operations** go through `Discuss.Repo` even from `discuss_auth` — auth app depends on core's repo.
- **Topics require authentication** — `auth_user_id` is set from `conn.assigns.current_user.id` in the controller.
- **No LiveView for topics** — standard Phoenix controllers + HEEx templates (layouts rendered as `layout: false` in controllers, using root layout only).
- **Dev dashboard** available at `/dev/dashboard`, mailbox preview at `/dev/mailbox`.

### Config

- `config/config.exs` — Base config
- `config/dev.exs` — DB: `postgres/postgres@localhost/discuss_dev`, port 4000
- `config/runtime.exs` — Production env vars (`DATABASE_URL`, `SECRET_KEY_BASE`)
- `config/test.exs` — Test DB config
