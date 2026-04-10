# Wokku Plugin for Claude Code

Official [Wokku](https://wokku.dev) plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Deploy and manage apps on Wokku — the open-source Heroku alternative — directly from Claude Code using natural language.

## Features

- **57 MCP tools** — 100% coverage of the Wokku API (apps, databases, domains, SSL, backups, releases, teams, notifications, and more)
- **4 guided skills** for common workflows:
  - `deploy-new-app` — full deploy walkthrough from git repo to running app
  - `troubleshoot` — systematic debugging with logs, health checks, and fix suggestions
  - `setup-github-deploy` — connect a GitHub repo for auto-deployment
  - `add-database` — create and link databases to apps
- **Zero dependencies** — pure Ruby stdlib, no gems required

## Install

```bash
/plugin marketplace add johannesdwicahyo/wokku-plugin
/plugin install wokku@wokku
```

You'll be prompted for:
- `WOKKU_API_URL` — defaults to `https://wokku.dev/api/v1`
- `WOKKU_API_TOKEN` — create one at [wokku.dev/dashboard/profile](https://wokku.dev/dashboard/profile)

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

## Self-Hosted Wokku

If you run your own Wokku instance, set `WOKKU_API_URL` to your instance URL:

```
WOKKU_API_URL=https://paas.mycompany.com/api/v1
```

## Requirements

- Ruby 3.0+ (only stdlib, no gems)
- A Wokku account (free at [wokku.dev](https://wokku.dev)) or self-hosted instance

## License

MIT
