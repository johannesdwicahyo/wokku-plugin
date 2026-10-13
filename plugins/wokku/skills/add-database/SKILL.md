---
description: Create a database on Wokku and link it to an app — sets connection URL as env var automatically
---

# Add Database to App

Create a new database and link it to an app so the connection URL is available as an env var.

## Steps

1. **Identify the app**
   - If user didn't specify, use `wokku_list_apps` and ask which one
   - Use `wokku_get_app` to get `server_id` (databases must be on the same server)

2. **Choose shared (free) or dedicated**
   - **Shared — default.** Free on every plan, instant. Engines: `postgres`, `mariadb`, `redis`.
     Call `wokku_enable_shared_addon` with `app_id` + `engine`. Provisioning is async:
     poll `wokku_list_addons` until it shows `status: running`.
     Sets `DATABASE_URL` (postgres), `MARIADB_URL` + `DATABASE_URL` (mariadb), `REDIS_URL` (redis).
     Size-capped by plan; postgres/mariadb backed up on request only, redis never backed up.
   - **Dedicated** — own container, nightly backups, uses one of the plan's dedicated slots.
     Engines: `postgres`, `mariadb`, `mongodb`, `redis`.
     - App already has a shared postgres/mariadb/redis → `wokku_upgrade_dedicated_addon` (migrates data, repoints the URL).
     - Otherwise → `wokku_create_database` (`service_type`, `name` default `{app}-{type}`, `server_id`),
       then `wokku_link_database`. It starts EMPTY.

3. **Verify**
   - Use `wokku_get_config` to confirm the connection URL is set
   - Use `wokku_get_logs` to check the app restarted cleanly

Recommend dedicated (nightly backups) if the database holds production data.
