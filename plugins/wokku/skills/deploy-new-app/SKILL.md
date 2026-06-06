---
description: Deploy a new app to Wokku from the current project — creates the app, sets config, and walks through git push deploy
---

# Deploy New App to Wokku

Guided workflow for deploying the current project to Wokku as a new app.

## Steps

1. **Check prerequisites**
   - Verify the current directory is a git repo (`git status`)
   - Detect the framework from files (`package.json`, `Gemfile`, `requirements.txt`, `go.mod`, `Dockerfile`)
   - Confirm with user which framework detected

2. **Get server info**
   - Use `wokku_list_servers` to show available servers
   - Ask user which server to deploy to (or default to the first one)

3. **Create the app**
   - Ask user for an app name (default: current directory name, lowercase with hyphens)
   - Validate: lowercase, alphanumeric + hyphens, 3-30 chars
   - Call `wokku_create_app` with the chosen name, server_id, and deploy_branch (default: "main")
   - Confirm creation and show the app ID

4. **Set environment variables** (optional)
   - Ask the user if they have env vars to set
   - If yes, collect KEY=VALUE pairs and call `wokku_set_config`
   - For common frameworks, suggest defaults:
     - Rails: `RAILS_MASTER_KEY`, `DATABASE_URL`
     - Node: `NODE_ENV=production`
     - Django: `SECRET_KEY`, `DEBUG=False`

5. **Add a database** (optional)
   - Ask if the app needs a database
   - If yes, suggest common choices (postgres, mysql, redis)
   - Use `wokku_create_database` then `wokku_link_database` to link it
   - Confirm that `DATABASE_URL` is now set automatically

6. **Walk through git push deploy**
   - Show the user the git remote command:
     ```bash
     git remote add dokku dokku@<server-host>:<app-name>
     git push dokku main
     ```
   - Get the server host from `wokku_get_server`
   - Tell user to run this in their terminal
   - After they push, use `wokku_get_logs` to show the deploy output

7. **Verify deployment**
   - Use `wokku_get_app` to check status
   - Use `wokku_list_domains` to show the default domain
   - Suggest adding a custom domain with `wokku_add_domain` if needed

## Tips

- Free tier is 1 eco container + 1 mini database. If user hits the limit, suggest upgrading at wokku.cloud/dashboard/billing
- For Rails apps, remind user to run `bin/rails credentials:edit` locally to set the master key
- For Docker apps, the `Dockerfile` takes precedence over buildpack detection
