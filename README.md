# Wokku Plugin for Claude Code

Official [Wokku](https://wokku.cloud) plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Deploy and manage apps on Wokku — the open-source Heroku alternative — directly from Claude Code using natural language.

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

## Self-Hosted Wokku

If you run your own Wokku instance, set `WOKKU_API_URL` to your instance URL:

```
WOKKU_API_URL=https://paas.mycompany.com/api/v1
```

The REST API is a managed-cloud feature. To enable it on a self-host, see the
[wokku self-host docs](https://wokku.cloud/docs/self-host#enabling-the-api).

## Requirements

- Ruby 3.0+ (only stdlib, no gems)
- A Wokku account (free at [wokku.cloud](https://wokku.cloud)) or self-hosted instance

## License

MIT
