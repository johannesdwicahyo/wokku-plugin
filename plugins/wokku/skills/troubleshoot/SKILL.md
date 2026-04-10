---
description: Systematic debugging for Wokku apps — check status, logs, health, deploys, and suggest fixes
---

# Troubleshoot Wokku App

Diagnose issues with a Wokku app using a systematic checklist.

## Steps

1. **Identify the app**
   - If user didn't specify, use `wokku_list_apps` and ask which one
   - Use `wokku_get_app` to get current state (status, server, deploy_branch)

2. **Check app status**
   - `running`: App is up. Continue to checking logs for runtime errors.
   - `stopped`: App was manually stopped. Ask if they want to start it with `wokku_start_app`.
   - `crashed`: App crashed. Go to logs immediately.
   - `deploying`: A deploy is in progress. Check `wokku_list_deploys` for status.

3. **Check recent deploys**
   - Use `wokku_list_deploys` to see deploy history
   - If latest deploy failed, use `wokku_get_deploy` for details
   - Common deploy failures:
     - Missing Procfile → suggest adding one
     - Buildpack detection failed → suggest a Dockerfile or explicit buildpack
     - Out of memory during build → suggest upgrading dyno tier

4. **Check logs**
   - Use `wokku_get_logs` with `lines: 200`
   - Look for patterns:
     - `ActiveRecord::ConnectionNotEstablished` → database not linked or DATABASE_URL missing
     - `Port 5000 already in use` → Procfile issue
     - `OOMKilled` → needs bigger dyno tier
     - `Missing RAILS_MASTER_KEY` → env var not set
     - Stack traces → actual code errors

5. **Check health checks**
   - Use `wokku_get_checks` to see current config
   - If health check path is `/` but app uses `/up` or `/health`, suggest updating with `wokku_update_checks`

6. **Check environment variables**
   - Use `wokku_get_config` to see what's set
   - Compare against what the framework needs:
     - Rails: `RAILS_MASTER_KEY`, `DATABASE_URL`, `SECRET_KEY_BASE`
     - Node: `NODE_ENV`, `PORT` (Dokku sets this automatically)
     - Django: `SECRET_KEY`, `DATABASE_URL`, `ALLOWED_HOSTS`
   - Suggest `wokku_set_config` to add missing ones

7. **Check database links**
   - Use `wokku_list_addons` to see linked databases
   - If no database but app expects one, use `wokku_create_database` + `wokku_link_database`

8. **Suggest fix**
   - Based on findings, propose specific actions
   - Ask user to confirm before making changes
   - After fix, use `wokku_restart_app` and verify with `wokku_get_logs`

## Common Issues Cheat Sheet

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| 500 on every request | DB not linked | `wokku_link_database` |
| Deploy fails at build | Missing Procfile | Add Procfile to repo |
| App crashes on start | Missing env var | `wokku_set_config` |
| Slow responses | Dyno too small | Scale up tier |
| SSL not working | DNS not pointed | Check domain A record |
