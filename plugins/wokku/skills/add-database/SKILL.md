---
description: Create a database on Wokku and link it to an app — sets connection URL as env var automatically
---

# Add Database to App

Create a new database and link it to an app so the connection URL is available as an env var.

## Steps

1. **Identify the app**
   - If user didn't specify, use `wokku_list_apps` and ask which one
   - Use `wokku_get_app` to get `server_id` (databases must be on the same server)

2. **Choose database type**
   - If not specified, ask which type they need:
     - `postgres` — most common, good default for relational data
     - `mysql` — if the app uses MySQL specifically
     - `mariadb` — MySQL-compatible fork
     - `redis` — cache, sessions, queues
     - `mongodb` — document database
     - `memcached` — simple cache
     - `rabbitmq`, `nats` — message queues
     - `elasticsearch`, `meilisearch` — search
     - `clickhouse` — analytics

3. **Create the database**
   - Default name: `{app_name}-{db_type}` (e.g., `my-app-postgres`)
   - Ask user to confirm or provide a custom name
   - Call `wokku_create_database` with `service_type`, `name`, and `server_id`

4. **Link to the app**
   - Call `wokku_link_database` with the new `database_id` and `app_id`
   - This automatically:
     - Sets `DATABASE_URL` (postgres/mysql/mariadb) or `REDIS_URL`, `MONGO_URL`, etc.
     - Restarts the app to pick up the new env var

5. **Verify**
   - Use `wokku_get_config` to confirm the connection URL is set
   - Use `wokku_get_logs` to check the app restarted cleanly
   - Suggest the user check their app can connect to the database

## Connection URL Reference

| Database | Env Var |
|----------|---------|
| postgres | `DATABASE_URL` |
| mysql | `DATABASE_URL` |
| mariadb | `DATABASE_URL` |
| redis | `REDIS_URL` |
| mongodb | `MONGO_URL` |
| memcached | `MEMCACHED_URL` |
| rabbitmq | `RABBITMQ_URL` |
| elasticsearch | `ELASTICSEARCH_URL` |

## Backup Reminder

- Free tier: 3 manual backups max, 1-day retention
- Basic tier ($1-2/mo): daily auto-backups, 7-day retention
- Standard tier ($4-6/mo): daily auto-backups, 30-day retention

Suggest upgrading if the database holds production data.
