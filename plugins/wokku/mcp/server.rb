#!/usr/bin/env ruby
# frozen_string_literal: true

# Wokku MCP Server
# Manage your Wokku apps, databases, and deployments from Claude Code.
#
# Quick install:
#   curl -fsSL https://raw.githubusercontent.com/johannesdwicahyo/wokku/main/mcp/server.rb -o wokku-mcp.rb
#   claude mcp add wokku \
#     -e WOKKU_API_URL=https://wokku.dev/api/v1 \
#     -e WOKKU_API_TOKEN=your-token-here \
#     -- ruby wokku-mcp.rb
#
# Full docs: https://github.com/johannesdwicahyo/wokku/blob/main/mcp/README.md

require "json"
require "net/http"
require "uri"

WOKKU_API_URL = ENV.fetch("WOKKU_API_URL", "https://wokku.dev/api/v1")
WOKKU_API_TOKEN = ENV.fetch("WOKKU_API_TOKEN", "")

def api_request(method, path, body = nil)
  uri = URI("#{WOKKU_API_URL}#{path}")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.open_timeout = 10
  http.read_timeout = 30

  request = case method
  when :get then Net::HTTP::Get.new(uri)
  when :post then Net::HTTP::Post.new(uri)
  when :put then Net::HTTP::Put.new(uri)
  when :patch then Net::HTTP::Patch.new(uri)
  when :delete then Net::HTTP::Delete.new(uri)
  end

  request["Authorization"] = "Bearer #{WOKKU_API_TOKEN}"
  request["Content-Type"] = "application/json"
  request["User-Agent"] = "wokku-mcp/1.0"
  request.body = body.to_json if body

  response = http.request(request)
  JSON.parse(response.body) rescue response.body
rescue Net::OpenTimeout, Net::ReadTimeout => e
  { error: "Request timed out: #{e.message}" }
rescue Errno::ECONNREFUSED
  { error: "Cannot connect to #{WOKKU_API_URL} — is the server running?" }
rescue => e
  { error: e.message }
end

def handle_tool(name, args)
  case name
  when "wokku_list_servers" then api_request(:get, "/servers")
  when "wokku_get_server" then api_request(:get, "/servers/#{args['server_id']}")
  when "wokku_server_status" then api_request(:get, "/servers/#{args['server_id']}/status")
  when "wokku_list_apps" then api_request(:get, "/apps")
  when "wokku_get_app" then api_request(:get, "/apps/#{args['app_id']}")
  when "wokku_create_app"
    body = {
      name: args["name"],
      server_id: args["server_id"],
      deploy_branch: args["deploy_branch"] || "main"
    }
    # Bundle v2 — optional box-model fields (ignored by pre-bundle-v2 servers)
    body[:box_size]                = args["box_size"]                if args["box_size"]
    body[:enabled_shared_engines]  = args["enabled_shared_engines"]  if args["enabled_shared_engines"].is_a?(Array)
    body[:dedicated_db_engine]     = args["dedicated_db_engine"]     if args["dedicated_db_engine"]
    body[:add_dedicated_redis]     = true                            if args["add_dedicated_redis"]
    api_request(:post, "/apps", body)
  when "wokku_update_app"
    body = {}
    body[:name] = args["name"] if args["name"]
    body[:deploy_branch] = args["deploy_branch"] if args["deploy_branch"]
    api_request(:put, "/apps/#{args['app_id']}", body)
  when "wokku_delete_app" then api_request(:delete, "/apps/#{args['app_id']}")
  when "wokku_restart_app" then api_request(:post, "/apps/#{args['app_id']}/restart")
  when "wokku_stop_app" then api_request(:post, "/apps/#{args['app_id']}/stop")
  when "wokku_start_app" then api_request(:post, "/apps/#{args['app_id']}/start")
  when "wokku_deploy_app" then api_request(:post, "/apps/#{args['app_id']}/deploy")
  when "wokku_get_config" then api_request(:get, "/apps/#{args['app_id']}/config")
  when "wokku_set_config" then api_request(:put, "/apps/#{args['app_id']}/config", args["vars"])
  when "wokku_unset_config" then api_request(:delete, "/apps/#{args['app_id']}/config", { keys: args["keys"] })
  when "wokku_list_domains" then api_request(:get, "/apps/#{args['app_id']}/domains")
  when "wokku_add_domain" then api_request(:post, "/apps/#{args['app_id']}/domains", { domain: args["domain"] })
  when "wokku_remove_domain" then api_request(:delete, "/apps/#{args['app_id']}/domains/#{args['domain_id']}")
  when "wokku_enable_ssl" then api_request(:post, "/apps/#{args['app_id']}/domains/#{args['domain_id']}/ssl")
  when "wokku_list_releases" then api_request(:get, "/apps/#{args['app_id']}/releases")
  when "wokku_get_release" then api_request(:get, "/apps/#{args['app_id']}/releases/#{args['release_id']}")
  when "wokku_rollback" then api_request(:post, "/apps/#{args['app_id']}/releases/#{args['release_id']}/rollback")
  when "wokku_get_ps" then api_request(:get, "/apps/#{args['app_id']}/ps")
  when "wokku_scale_app"
    scaling = {}
    scaling["web"] = args["web"] if args["web"]
    scaling["worker"] = args["worker"] if args["worker"]
    api_request(:put, "/apps/#{args['app_id']}/ps", { scaling: scaling })
  when "wokku_get_checks" then api_request(:get, "/apps/#{args['app_id']}/checks")
  when "wokku_update_checks" then api_request(:put, "/apps/#{args['app_id']}/checks", args["checks"])
  when "wokku_get_logs" then api_request(:get, "/apps/#{args['app_id']}/logs?lines=#{args['lines'] || 100}")
  when "wokku_list_deploys" then api_request(:get, "/apps/#{args['app_id']}/deploys")
  when "wokku_get_deploy" then api_request(:get, "/apps/#{args['app_id']}/deploys/#{args['deploy_id']}")
  when "wokku_list_addons" then api_request(:get, "/apps/#{args['app_id']}/addons")
  when "wokku_add_addon" then api_request(:post, "/apps/#{args['app_id']}/addons", { service_type: args["service_type"], name: args["name"] })
  when "wokku_remove_addon" then api_request(:delete, "/apps/#{args['app_id']}/addons/#{args['addon_id']}")
  # Bundle v2 — shared addon enable/disable + dedicated upgrade
  when "wokku_enable_shared_addon"
    api_request(:post, "/apps/#{args['app_id']}/addons/shared", { engine: args["engine"] })
  when "wokku_disable_shared_addon"
    api_request(:delete, "/apps/#{args['app_id']}/addons/shared/#{args['engine']}")
  when "wokku_upgrade_dedicated_addon"
    api_request(:post, "/apps/#{args['app_id']}/addons/dedicated", { engine: args["engine"] })
  when "wokku_set_https"
    api_request(:patch, "/apps/#{args['app_id']}/https", { enabled: args["enabled"] })
  when "wokku_set_cdn"
    api_request(:patch, "/apps/#{args['app_id']}/cdn", { enabled: args["enabled"] })
  when "wokku_set_maintenance"
    api_request(:patch, "/apps/#{args['app_id']}/maintenance", { enabled: args["enabled"] })
  when "wokku_github_connect"
    api_request(:post, "/apps/#{args['app_id']}/github_connect", { repo: args["repo"], branch: args["branch"] || "main" })
  when "wokku_github_disconnect"
    api_request(:delete, "/apps/#{args['app_id']}/github_disconnect")
  when "wokku_list_log_drains" then api_request(:get, "/apps/#{args['app_id']}/log_drains")
  when "wokku_add_log_drain" then api_request(:post, "/apps/#{args['app_id']}/log_drains", { url: args["url"] })
  when "wokku_remove_log_drain" then api_request(:delete, "/apps/#{args['app_id']}/log_drains/#{args['drain_id']}")
  when "wokku_list_templates" then api_request(:get, "/templates")
  when "wokku_get_template" then api_request(:get, "/templates/#{args['template_id']}")
  when "wokku_deploy_template"
    api_request(:post, "/templates/deploy", { slug: args["template_slug"], server_id: args["server_id"], name: args["app_name"] })
  when "wokku_list_databases" then api_request(:get, "/databases")
  when "wokku_get_database" then api_request(:get, "/databases/#{args['database_id']}")
  when "wokku_create_database"
    api_request(:post, "/databases", { service_type: args["service_type"], name: args["name"], server_id: args["server_id"] })
  when "wokku_delete_database" then api_request(:delete, "/databases/#{args['database_id']}")
  when "wokku_link_database" then api_request(:post, "/databases/#{args['database_id']}/link", { app_id: args["app_id"] })
  when "wokku_unlink_database" then api_request(:post, "/databases/#{args['database_id']}/unlink", { app_id: args["app_id"] })
  when "wokku_list_backups" then api_request(:get, "/databases/#{args['database_id']}/backups")
  when "wokku_create_backup" then api_request(:post, "/databases/#{args['database_id']}/backups")
  when "wokku_list_ssh_keys" then api_request(:get, "/ssh_keys")
  when "wokku_add_ssh_key" then api_request(:post, "/ssh_keys", { name: args["name"], public_key: args["public_key"] })
  when "wokku_remove_ssh_key" then api_request(:delete, "/ssh_keys/#{args['key_id']}")
  when "wokku_list_teams" then api_request(:get, "/teams")
  when "wokku_create_team" then api_request(:post, "/teams", { name: args["name"] })
  when "wokku_list_team_members" then api_request(:get, "/teams/#{args['team_id']}/members")
  when "wokku_add_team_member" then api_request(:post, "/teams/#{args['team_id']}/members", { email: args["email"], role: args["role"] || "member" })
  when "wokku_remove_team_member" then api_request(:delete, "/teams/#{args['team_id']}/members/#{args['member_id']}")
  when "wokku_list_notifications" then api_request(:get, "/notifications")
  when "wokku_create_notification"
    api_request(:post, "/notifications", { channel: args["channel"], event: args["event"], config: args["config"] })
  when "wokku_delete_notification" then api_request(:delete, "/notifications/#{args['notification_id']}")
  when "wokku_list_activities" then api_request(:get, "/activities?limit=#{args['limit'] || 20}")
  when "wokku_get_app_metrics"
    api_request(:get, "/apps/#{args['app_id']}/metrics")
  when "wokku_get_app_monitor"
    api_request(:get, "/apps/#{args['app_id']}/monitor")
  when "wokku_get_app_vitals"
    api_request(:get, "/apps/#{args['app_id']}/vitals")
  when "wokku_get_database_monitor"
    api_request(:get, "/databases/#{args['database_id']}/monitor")
  # Cluster B — app lifecycle (rename / clone / lock / unlock / transfer)
  when "wokku_rename_app"
    api_request(:patch, "/apps/#{args['app_id']}/rename", { name: args["new_name"] })
  when "wokku_clone_app"
    api_request(:post, "/apps/#{args['app_id']}/clone",
                { name: args["new_name"], skip_deploy: args.fetch("skip_deploy", true) })
  when "wokku_lock_app"
    api_request(:post, "/apps/#{args['app_id']}/lock")
  when "wokku_unlock_app"
    api_request(:post, "/apps/#{args['app_id']}/unlock")
  when "wokku_transfer_app"
    api_request(:post, "/apps/#{args['app_id']}/transfer", { recipient_email: args["recipient_email"] })
  else
    { error: "Unknown tool: #{name}" }
  end
end

# Tool definitions — 55 tools, 100% coverage of Wokku API v1
TOOLS = [
  { name: "wokku_list_servers", description: "List all connected Dokku servers", inputSchema: { type: "object", properties: {} } },
  { name: "wokku_get_server", description: "Get server details", inputSchema: { type: "object", properties: { server_id: { type: "string", description: "The server ID" } }, required: [ "server_id" ] } },
  { name: "wokku_server_status", description: "Get server health (CPU, memory, disk)", inputSchema: { type: "object", properties: { server_id: { type: "string", description: "The server ID" } }, required: [ "server_id" ] } },
  { name: "wokku_list_apps", description: "List all applications", inputSchema: { type: "object", properties: {} } },
  { name: "wokku_get_app", description: "Get app details", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID or name" } }, required: [ "app_id" ] } },
  { name: "wokku_create_app", description: "Create a new application. Bundle v2 (optional): box_size + enabled_shared_engines + dedicated_db_engine + add_dedicated_redis configure the box at creation. Older servers ignore these fields.", inputSchema: { type: "object", properties: { name: { type: "string", description: "App name" }, server_id: { type: "integer", description: "Server ID" }, deploy_branch: { type: "string", description: "Deploy branch (default: main)" }, box_size: { type: "string", description: "Bundle v2: sleeping|small|medium|large|xlarge", enum: [ "sleeping", "small", "medium", "large", "xlarge" ] }, enabled_shared_engines: { type: "array", items: { type: "string", enum: [ "postgres", "redis", "memcached", "rabbitmq", "meilisearch" ] }, description: "Bundle v2: shared engines to attach at creation. Free plan limited to postgres+redis." }, dedicated_db_engine: { type: "string", enum: [ "postgres", "mysql", "mongodb" ], description: "Bundle v2: spin up a dedicated database alongside the box (paid plans only)" }, add_dedicated_redis: { type: "boolean", description: "Bundle v2: spin up a dedicated Redis alongside the box (paid plans only)" } }, required: [ "name", "server_id" ] } },
  { name: "wokku_update_app", description: "Update app settings (rename, change branch)", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, name: { type: "string", description: "New name" }, deploy_branch: { type: "string", description: "New branch" } }, required: [ "app_id" ] } },
  { name: "wokku_delete_app", description: "Delete an application", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_restart_app", description: "Restart an application", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_stop_app", description: "Stop an application", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_start_app", description: "Start a stopped application", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_deploy_app", description: "Trigger a deploy for an app (rebuilds and deploys the latest code)", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_get_config", description: "Get environment variables", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_set_config", description: "Set environment variables", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, vars: { type: "object", description: "Key-value pairs" } }, required: [ "app_id", "vars" ] } },
  { name: "wokku_unset_config", description: "Remove environment variables", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, keys: { type: "array", items: { type: "string" }, description: "Keys to remove" } }, required: [ "app_id", "keys" ] } },
  { name: "wokku_list_domains", description: "List domains for an app", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_add_domain", description: "Add a custom domain", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, domain: { type: "string", description: "Domain name" } }, required: [ "app_id", "domain" ] } },
  { name: "wokku_remove_domain", description: "Remove a domain", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, domain_id: { type: "string", description: "The domain ID" } }, required: [ "app_id", "domain_id" ] } },
  { name: "wokku_enable_ssl", description: "Enable SSL for a domain", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, domain_id: { type: "string", description: "The domain ID" } }, required: [ "app_id", "domain_id" ] } },
  { name: "wokku_list_releases", description: "List releases", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_get_release", description: "Get release details", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, release_id: { type: "string", description: "The release ID" } }, required: [ "app_id", "release_id" ] } },
  { name: "wokku_rollback", description: "Rollback to a previous release", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, release_id: { type: "string", description: "The release ID" } }, required: [ "app_id", "release_id" ] } },
  { name: "wokku_get_ps", description: "Get process/dyno info", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_scale_app", description: "Scale web/worker dynos", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, web: { type: "integer", description: "Web dynos" }, worker: { type: "integer", description: "Worker dynos" } }, required: [ "app_id" ] } },
  { name: "wokku_get_checks", description: "Get health check config", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_update_checks", description: "Update health checks", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, checks: { type: "object", description: "Health check settings" } }, required: [ "app_id", "checks" ] } },
  { name: "wokku_get_logs", description: "Get application logs", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, lines: { type: "integer", description: "Number of lines (default: 100)" } }, required: [ "app_id" ] } },
  { name: "wokku_list_deploys", description: "List deploy history", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_get_deploy", description: "Get deploy details", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, deploy_id: { type: "string", description: "The deploy ID" } }, required: [ "app_id", "deploy_id" ] } },
  { name: "wokku_list_addons", description: "List linked databases", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_add_addon", description: "[LEGACY pre-Bundle-v2] Add a database to an app. Bundle v2 servers return 410 — use wokku_enable_shared_addon or wokku_upgrade_dedicated_addon instead.", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, service_type: { type: "string", description: "Database type" }, name: { type: "string", description: "Optional name" } }, required: [ "app_id", "service_type" ] } },
  { name: "wokku_remove_addon", description: "Remove a database from an app", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, addon_id: { type: "string", description: "The addon ID" } }, required: [ "app_id", "addon_id" ] } },
  # Bundle v2 — shared addon enable/disable + dedicated upgrade
  { name: "wokku_enable_shared_addon", description: "Bundle v2: enable a shared engine on an app's box. Free plan limited to postgres+redis; other plans can pick from all 5.", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, engine: { type: "string", enum: [ "postgres", "redis", "memcached", "rabbitmq", "meilisearch" ], description: "Shared engine to enable" } }, required: [ "app_id", "engine" ] } },
  { name: "wokku_disable_shared_addon", description: "Bundle v2: disable a shared engine on an app's box. Destroys the shared tenant + data.", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, engine: { type: "string", enum: [ "postgres", "redis", "memcached", "rabbitmq", "meilisearch" ], description: "Shared engine to disable" } }, required: [ "app_id", "engine" ] } },
  { name: "wokku_upgrade_dedicated_addon", description: "Bundle v2: upgrade a box to a dedicated database (postgres|mysql|mongodb) or Redis. Pg/Redis migrate from shared (data preserved). MySQL/MongoDB are fresh-create. Quota: 3 per plan; size follows the box size.", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, engine: { type: "string", enum: [ "postgres", "mysql", "mongodb", "redis" ], description: "Engine to provision as dedicated" } }, required: [ "app_id", "engine" ] } },
  { name: "wokku_list_log_drains", description: "List log drains", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_add_log_drain", description: "Add a log drain", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, url: { type: "string", description: "Drain URL" } }, required: [ "app_id", "url" ] } },
  { name: "wokku_remove_log_drain", description: "Remove a log drain", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, drain_id: { type: "string", description: "The drain ID" } }, required: [ "app_id", "drain_id" ] } },
  { name: "wokku_list_templates", description: "List all templates", inputSchema: { type: "object", properties: {} } },
  { name: "wokku_get_template", description: "Get template details", inputSchema: { type: "object", properties: { template_id: { type: "string", description: "Template ID or slug" } }, required: [ "template_id" ] } },
  { name: "wokku_deploy_template", description: "Deploy a 1-click template", inputSchema: { type: "object", properties: { template_slug: { type: "string", description: "Template slug" }, server_id: { type: "integer", description: "Server ID" }, app_name: { type: "string", description: "App name" } }, required: [ "template_slug", "server_id" ] } },
  { name: "wokku_list_databases", description: "List all databases", inputSchema: { type: "object", properties: {} } },
  { name: "wokku_get_database", description: "Get database details", inputSchema: { type: "object", properties: { database_id: { type: "string", description: "The database ID" } }, required: [ "database_id" ] } },
  { name: "wokku_create_database", description: "Create a database", inputSchema: { type: "object", properties: { service_type: { type: "string", description: "Database type" }, name: { type: "string", description: "Name" }, server_id: { type: "integer", description: "Server ID" } }, required: [ "service_type", "name", "server_id" ] } },
  { name: "wokku_delete_database", description: "Delete a database", inputSchema: { type: "object", properties: { database_id: { type: "string", description: "The database ID" } }, required: [ "database_id" ] } },
  { name: "wokku_link_database", description: "Link database to an app", inputSchema: { type: "object", properties: { database_id: { type: "string", description: "The database ID" }, app_id: { type: "string", description: "The app ID" } }, required: [ "database_id", "app_id" ] } },
  { name: "wokku_unlink_database", description: "Unlink database from an app", inputSchema: { type: "object", properties: { database_id: { type: "string", description: "The database ID" }, app_id: { type: "string", description: "The app ID" } }, required: [ "database_id", "app_id" ] } },
  { name: "wokku_list_backups", description: "List backups", inputSchema: { type: "object", properties: { database_id: { type: "string", description: "The database ID" } }, required: [ "database_id" ] } },
  { name: "wokku_create_backup", description: "Create a backup", inputSchema: { type: "object", properties: { database_id: { type: "string", description: "The database ID" } }, required: [ "database_id" ] } },
  { name: "wokku_list_ssh_keys", description: "List SSH keys", inputSchema: { type: "object", properties: {} } },
  { name: "wokku_add_ssh_key", description: "Add an SSH key", inputSchema: { type: "object", properties: { name: { type: "string", description: "Key name" }, public_key: { type: "string", description: "Public key" } }, required: [ "name", "public_key" ] } },
  { name: "wokku_remove_ssh_key", description: "Remove an SSH key", inputSchema: { type: "object", properties: { key_id: { type: "string", description: "The key ID" } }, required: [ "key_id" ] } },
  { name: "wokku_list_teams", description: "List teams", inputSchema: { type: "object", properties: {} } },
  { name: "wokku_create_team", description: "Create a team", inputSchema: { type: "object", properties: { name: { type: "string", description: "Team name" } }, required: [ "name" ] } },
  { name: "wokku_list_team_members", description: "List team members", inputSchema: { type: "object", properties: { team_id: { type: "string", description: "The team ID" } }, required: [ "team_id" ] } },
  { name: "wokku_add_team_member", description: "Invite a team member", inputSchema: { type: "object", properties: { team_id: { type: "string", description: "The team ID" }, email: { type: "string", description: "Email" }, role: { type: "string", description: "Role: viewer, member, admin" } }, required: [ "team_id", "email" ] } },
  { name: "wokku_remove_team_member", description: "Remove a team member", inputSchema: { type: "object", properties: { team_id: { type: "string", description: "The team ID" }, member_id: { type: "string", description: "The member ID" } }, required: [ "team_id", "member_id" ] } },
  { name: "wokku_list_notifications", description: "List notification channels", inputSchema: { type: "object", properties: {} } },
  { name: "wokku_create_notification", description: "Create a notification channel", inputSchema: { type: "object", properties: { channel: { type: "string", description: "Channel type" }, event: { type: "string", description: "Event type" }, config: { type: "object", description: "Channel config" } }, required: [ "channel", "event", "config" ] } },
  { name: "wokku_delete_notification", description: "Delete a notification channel", inputSchema: { type: "object", properties: { notification_id: { type: "string", description: "The notification ID" } }, required: [ "notification_id" ] } },
  { name: "wokku_list_activities", description: "List recent activity log", inputSchema: { type: "object", properties: { limit: { type: "integer", description: "Number of entries (default: 20)" } } } },
  {
    name: "wokku_set_https",
    description: "Enable or disable HTTPS redirect for an app.",
    inputSchema: {
      type: "object",
      properties: {
        app_id:  { type: "string", description: "The app ID" },
        enabled: { type: "boolean", description: "true to enable, false to disable" }
      },
      required: [ "app_id", "enabled" ]
    }
  },
  {
    name: "wokku_set_cdn",
    description: "Enable or disable the Cloudflare CDN proxy on an app's DNS record. DNS propagation may take a minute.",
    inputSchema: {
      type: "object",
      properties: {
        app_id:  { type: "string", description: "The app ID" },
        enabled: { type: "boolean", description: "true to enable, false to disable" }
      },
      required: [ "app_id", "enabled" ]
    }
  },
  {
    name: "wokku_set_maintenance",
    description: "Enable or disable maintenance mode for an app (serves a 503 page instead of the app).",
    inputSchema: {
      type: "object",
      properties: {
        app_id:  { type: "string", description: "The app ID" },
        enabled: { type: "boolean", description: "true to enable, false to disable" }
      },
      required: [ "app_id", "enabled" ]
    }
  },
  {
    name: "wokku_github_connect",
    description: "Connect a GitHub repository to an app for auto-deploy.",
    inputSchema: {
      type: "object",
      properties: {
        app_id: { type: "string", description: "The app ID" },
        repo:   { type: "string", description: "owner/repo (e.g. johannes/myapp)" },
        branch: { type: "string", description: "Branch to track (default: main)" }
      },
      required: [ "app_id", "repo" ]
    }
  },
  {
    name: "wokku_github_disconnect",
    description: "Disconnect the GitHub repository from an app.",
    inputSchema: {
      type: "object",
      properties: {
        app_id: { type: "string", description: "The app ID" }
      },
      required: [ "app_id" ]
    }
  },
  {
    name: "wokku_get_app_metrics",
    description: "Get an app's stored CPU + memory metrics (last 60 minute rows + last 24 hourly buckets). Read-only.",
    inputSchema: {
      type: "object",
      properties: { app_id: { type: "string", description: "The app ID" } },
      required: [ "app_id" ]
    }
  },
  {
    name: "wokku_get_app_monitor",
    description: "Get HTTP request stats for an app (last 24h: totals, 5-min buckets, top 10 slow URLs). Read-only.",
    inputSchema: {
      type: "object",
      properties: { app_id: { type: "string", description: "The app ID" } },
      required: [ "app_id" ]
    }
  },
  {
    name: "wokku_get_app_vitals",
    description: "Get Core Web Vitals (CLS/LCP/INP/FCP/TTFB) p50/p75/p95 for an app — last 7 days, latest + history per metric. Read-only.",
    inputSchema: {
      type: "object",
      properties: { app_id: { type: "string", description: "The app ID" } },
      required: [ "app_id" ]
    }
  },
  {
    name: "wokku_get_database_monitor",
    description: "Get the latest database stats snapshot (active connections, cache hit ratio, size, top queries). Read-only.",
    inputSchema: {
      type: "object",
      properties: { database_id: { type: "string", description: "The database ID" } },
      required: [ "database_id" ]
    }
  },
  # Cluster B — app lifecycle (rename / clone / lock / unlock / transfer)
  {
    name: "wokku_rename_app",
    description: "Rename an app. The dokku-side rename preserves domains, but this BREAKS deployed bookmarks to the app's auto-generated wokku.cloud subdomain.",
    inputSchema: {
      type: "object",
      properties: {
        app_id:   { type: "string", description: "The current app ID" },
        new_name: { type: "string", description: "New app name (lowercase, 2-50 chars, alphanumeric and hyphens)" }
      },
      required: [ "app_id", "new_name" ]
    }
  },
  {
    name: "wokku_clone_app",
    description: "Clone an app's config + buildpacks + nginx. Does NOT carry env vars, databases, or storage. The new AppRecord points to the same server.",
    inputSchema: {
      type: "object",
      properties: {
        app_id:      { type: "string", description: "Source app ID" },
        new_name:    { type: "string", description: "New app name" },
        skip_deploy: { type: "boolean", description: "If true (default), dokku won't try to redeploy after cloning" }
      },
      required: [ "app_id", "new_name" ]
    }
  },
  {
    name: "wokku_lock_app",
    description: "Set the dokku deploy lock on an app. While locked, both git push and API-triggered deploys will be refused.",
    inputSchema: {
      type: "object",
      properties: { app_id: { type: "string", description: "The app ID" } },
      required: [ "app_id" ]
    }
  },
  {
    name: "wokku_unlock_app",
    description: "Release the dokku deploy lock on an app.",
    inputSchema: {
      type: "object",
      properties: { app_id: { type: "string", description: "The app ID" } },
      required: [ "app_id" ]
    }
  },
  {
    name: "wokku_transfer_app",
    description: "Initiate transfer of an app to another Wokku user (identified by email). Recipient must accept via the emailed link before ownership moves.",
    inputSchema: {
      type: "object",
      properties: {
        app_id:          { type: "string", description: "The app ID" },
        recipient_email: { type: "string", description: "Recipient's existing Wokku account email" }
      },
      required: [ "app_id", "recipient_email" ]
    }
  }
].freeze

$stdout.sync = true
$stderr.sync = true

loop do
  line = $stdin.gets
  break unless line

  begin
    msg = JSON.parse(line)
    id = msg["id"]

    case msg["method"]
    when "initialize"
      $stdout.puts JSON.generate({ jsonrpc: "2.0", id: id, result: { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "wokku", version: "1.0.0" } } })
    when "notifications/initialized"
      # No response needed
    when "tools/list"
      $stdout.puts JSON.generate({ jsonrpc: "2.0", id: id, result: { tools: TOOLS } })
    when "tools/call"
      tool_name = msg.dig("params", "name")
      arguments = msg.dig("params", "arguments") || {}
      result = handle_tool(tool_name, arguments)
      $stdout.puts JSON.generate({ jsonrpc: "2.0", id: id, result: { content: [ { type: "text", text: JSON.pretty_generate(result) } ] } })
    else
      $stdout.puts JSON.generate({ jsonrpc: "2.0", id: id, error: { code: -32601, message: "Method not found: #{msg['method']}" } })
    end
  rescue => e
    $stderr.puts "Error: #{e.message}"
  end
end
