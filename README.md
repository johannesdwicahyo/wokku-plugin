# Wokku Plugin for Claude Code

Official [Wokku Cloud](https://wokku.cloud) plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Deploy and manage apps on Wokku Cloud directly from Claude Code using natural language.

> **Wokku Cloud only.** This plugin wraps the Wokku REST API, which ships only with the managed Wokku Cloud product. The open-source Wokku web UI ([github.com/johannesdwicahyo/wokku](https://github.com/johannesdwicahyo/wokku)) does not expose `/api/v1`, so the plugin cannot point at a self-hosted Wokku install.

## Features

- **57 MCP tools** — 100% coverage of the Wokku API (apps, databases, domains, SSL, backups, releases, teams, notifications, and more)
- **4 guided skills** for common workflows:
  - `deploy-new-app` — full deploy walkthrough from git repo to running app
  - `troubleshoot` — systematic debugging with logs, health checks, and fix suggestions
  - `setup-github-deploy` — connect a GitHub repo for auto-deployment
  - `add-database` — create and link databases to apps
- **Zero gem dependencies** — pure Ruby stdlib, runs anywhere Claude Code does

## Install

```bash
/plugin marketplace add johannesdwicahyo/wokku-plugin
/plugin install wokku@wokku
```

You'll be prompted for:
- `WOKKU_API_URL` — defaults to `https://wokku.cloud/api/v1`
- `WOKKU_API_TOKEN` — create one at [wokku.cloud/dashboard/profile](https://wokku.cloud/dashboard/profile)

Restart Claude Code to load the plugin.

## Usage

Once installed, you can ask Claude things like:

- *"Deploy this project to Wokku as my-app"*
- *"Show me the logs for my-app"*
- *"Troubleshoot why my-app is crashing"*
- *"Create a PostgreSQL database and link it to my-app"*
- *"Scale my-app to 2 web dynos"*
- *"Rollback my-app to the previous release"*
- *"Add blog.example.com to my-app and enable SSL"*
- *"Attach a shared Redis to my-app"* *(new in v0.2.0)*
- *"Promote my-app's Postgres to a dedicated container"* *(new in v0.2.0)*

## What's New in v0.2.0 (May 2026)

The May release of [Wokku](https://github.com/johannesdwicahyo/wokku)
introduced shared-engine add-ons (Postgres / Redis / Memcached / RabbitMQ /
Meilisearch — see the
[dokku-shared-*](https://github.com/johannesdwicahyo?tab=repositories&q=dokku-shared)
plugin family) plus a dedicated-upgrade flow. The plugin gained corresponding
MCP tools:

- `wokku_attach_shared_addon`, `wokku_detach_shared_addon`
- `wokku_upgrade_to_dedicated` (Postgres / Redis)
- `wokku_list_addons` now distinguishes shared vs dedicated and shows
  per-tenant usage (size, connection count)

The `add-database` skill was updated to prompt between *shared free*
(default, instant) and *dedicated paid* (consumes one of the 3 dedicated
slots on Solo / Pro plans) when you ask for a new DB.

## Requirements

- Ruby 3.0+ (only stdlib, no gems)
- A Wokku Cloud account (free at [wokku.cloud](https://wokku.cloud))

## License

MIT
