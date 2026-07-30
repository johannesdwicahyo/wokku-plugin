#!/usr/bin/env ruby
# frozen_string_literal: true

# Wokku MCP Server
# Manage your Wokku apps, databases, and deployments from Claude Code.
#
# Quick install:
#   curl -fsSL https://raw.githubusercontent.com/johannesdwicahyo/wokku-plugin/main/plugins/wokku/mcp/server.rb -o wokku-mcp.rb
#   claude mcp add wokku \
#     -e WOKKU_API_URL=https://wokku.cloud/api/v1 \
#     -e WOKKU_API_TOKEN=your-token-here \
#     -- ruby wokku-mcp.rb
#
# Full docs: https://github.com/johannesdwicahyo/wokku/blob/main/mcp/README.md

require "json"
require "net/http"
require "uri"
require "tmpdir"

WOKKU_API_URL = ENV.fetch("WOKKU_API_URL", "https://wokku.cloud/api/v1")

# Token resolution: explicit env wins, then the wokku CLI's saved login
# (~/.wokku/config.json, written by `wokku auth:login`'s device flow).
# The MCP server runs on the user's machine, so one browser-hop login
# authenticates BOTH surfaces — no manual token pasting for MCP.
WOKKU_API_TOKEN = begin
  env_token = ENV.fetch("WOKKU_API_TOKEN", "")
  if !env_token.empty?
    env_token
  else
    cli_config = File.join(Dir.home, ".wokku", "config.json")
    if File.readable?(cli_config)
      JSON.parse(File.read(cli_config))["token"].to_s rescue ""
    else
      ""
    end
  end
end
NO_TOKEN_HINT = "No Wokku token found. Run `wokku auth:login` (one browser hop; saves to " \
                "~/.wokku/config.json, which this MCP server reads too) or set WOKKU_API_TOKEN " \
                "in the plugin env.".freeze

# Sent as X-Wokku-Client-Version on every request so the API's client_version
# concern can flag outdated MCP servers (see MIN_VERSIONS in
# app/controllers/concerns/client_version.rb) and /doctor can surface it.
SERVER_VERSION = "1.2.0"

# Log endpoint to stderr so Claude Code's MCP debug logs show which
# Wokku instance (managed vs self-hosted OSS) the plugin is talking to.
$stderr.puts "wokku-mcp: connecting to #{WOKKU_API_URL} (#{WOKKU_API_URL.include?('wokku.cloud') ? 'managed' : 'self-hosted'})"
$stderr.puts "wokku-mcp: token source: #{ENV["WOKKU_API_TOKEN"].to_s.empty? ? (WOKKU_API_TOKEN.empty? ? 'NONE' : '~/.wokku/config.json (CLI login)') : 'plugin env'}"

def api_request(method, path, body = nil)
  # Short-circuit locally when unauthenticated: better than a network
  # round-trip, and the hint names the one command that fixes it.
  return { error: "Missing Wokku token", error_code: "missing_token", hint: NO_TOKEN_HINT } if WOKKU_API_TOKEN.empty?

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
  request["User-Agent"] = "wokku-mcp/#{SERVER_VERSION}"
  request["X-Wokku-Client"] = "mcp"
  request["X-Wokku-Client-Version"] = SERVER_VERSION
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

# wokku_deploy_tarball — Track A Phase 4a Task 6. Deploys a local directory
# without a git remote: tar it up, request a presigned upload slot, PUT the
# tarball straight to the bucket (no auth header — the URL itself is the
# credential), create the deploy from the resulting archive_key, then poll
# deploys#show until it reaches a terminal state.
DEPLOY_POLL_INTERVAL = 3
# TarballDeployJob's own build timeout is 15 minutes (see app/jobs/
# tarball_deploy_job.rb); poll a little past that so we always see the
# job's own timed_out transition rather than giving up first.
DEPLOY_POLL_MAX_ATTEMPTS = (16 * 60) / DEPLOY_POLL_INTERVAL
TERMINAL_DEPLOY_STATUSES = %w[succeeded failed timed_out].freeze

def error_result?(result)
  result.is_a?(Hash) && (result["error"] || result[:error])
end

# Builds a .tar.gz of `path` at `archive_path`. Uses `git archive` (which
# only ever includes committed, non-ignored files) when `path` is a git
# repo; otherwise falls back to plain `tar` with sensible excludes so
# .git/node_modules/tmp/log never end up in the uploaded archive.
def build_tarball!(path, archive_path)
  if Dir.exist?(File.join(path, ".git"))
    ok = system("git", "-C", path, "archive", "--format=tar.gz", "--output=#{archive_path}", "HEAD")
    raise "git archive failed (is #{path} a git repo with at least one commit?)" unless ok
  else
    # COPYFILE_DISABLE stops macOS bsdtar from packing ._AppleDouble metadata
    # files, which make nixpacks builds fail host-side (no-op on Linux).
    ok = system({ "COPYFILE_DISABLE" => "1" }, "tar", "-czf", archive_path,
      "--exclude=.git", "--exclude=node_modules", "--exclude=tmp", "--exclude=log",
      "-C", path, ".")
    raise "tar failed while archiving #{path}" unless ok
  end
end

# `git archive HEAD` deploys the committed tree only — any uncommitted
# changes in the worktree are silently left out, which is easy to miss
# (the tool still "succeeds"). When `path` is a git repo with a dirty
# worktree, returns a warning string to surface to the model; nil
# otherwise (clean tree, non-git directory, or git isn't available).
def dirty_worktree_warning(path)
  return nil unless Dir.exist?(File.join(path, ".git"))

  porcelain = IO.popen([ "git", "-C", path, "status", "--porcelain" ], &:read)
  return nil unless $?&.success?
  return nil if porcelain.to_s.strip.empty?

  "worktree has uncommitted changes — deployed HEAD only; commit first to include them"
rescue
  nil
end

# PUTs the tarball straight to the presigned URL. No Authorization header —
# the signature embedded in the URL query string is the credential; adding
# our own would just break the signature. Returns nil on success, or an
# error hash on failure.
def upload_tarball(upload_url, archive_path)
  uri = URI(upload_url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.open_timeout = 10
  http.read_timeout = 120

  request = Net::HTTP::Put.new(uri)
  request["Content-Type"] = "application/gzip"
  request.body = File.binread(archive_path)

  response = http.request(request)
  return nil if response.is_a?(Net::HTTPSuccess)

  { error: "tarball upload failed: HTTP #{response.code} #{response.message}" }
rescue => e
  { error: "tarball upload failed: #{e.message}" }
end

# A transient network blip during polling (timeout, connection refused,
# DNS hiccup — anything api_request rescues into {error: "..."}) must never
# be mistaken for "the deploy has no status, so we're done": that used to
# silently return {deploy_id: nil, status: nil}, discarding the actual error
# and telling the model the deploy vanished. Instead we retry through
# transient errors (same poll interval) up to MAX_CONSECUTIVE_POLL_ERRORS
# in a row; a real response resets the counter. Only after that many
# consecutive failures do we give up, and even then we preserve the error
# message plus a hint to check the deploy directly — we never fabricate a
# status.
MAX_CONSECUTIVE_POLL_ERRORS = 5

def poll_deploy(app_id, deploy_id)
  result = nil
  consecutive_errors = 0

  DEPLOY_POLL_MAX_ATTEMPTS.times do
    result = api_request(:get, "/apps/#{app_id}/deploys/#{deploy_id}")

    if error_result?(result) && !status_present?(result)
      consecutive_errors += 1
      if consecutive_errors >= MAX_CONSECUTIVE_POLL_ERRORS
        return summarize_deploy(result).merge(
          deploy_id: deploy_id,
          polling_errored: true,
          note: "Polling failed #{consecutive_errors} times in a row and gave up. The deploy may still be running server-side — check wokku_get_deploy with deploy_id #{deploy_id}."
        )
      end

      sleep DEPLOY_POLL_INTERVAL
      next
    end

    consecutive_errors = 0
    status = status_present?(result) ? (result["status"] || result[:status]) : nil
    # Not the retried "error, no status" shape (handled above), but also not
    # a recognizable {status: ...} deploy payload — an unexpected shape
    # (non-Hash body, or a Hash with neither error nor status). Surface it
    # as-is rather than either discarding it or spinning for the full poll
    # budget on something that will never change.
    return summarize_deploy(result) if !result.is_a?(Hash) || status.nil? || TERMINAL_DEPLOY_STATUSES.include?(status.to_s)

    sleep DEPLOY_POLL_INTERVAL
  end

  summarize_deploy(result).merge(polling_timed_out: true, note: "Gave up polling after ~16 minutes; the deploy may still be running server-side. Check wokku_get_deploy.")
end

def status_present?(result)
  result.is_a?(Hash) && !(result["status"] || result[:status]).nil?
end

def summarize_deploy(result)
  return result unless result.is_a?(Hash)

  error = result["error"] || result[:error]
  if error && !status_present?(result)
    out = { error: error }
    out[:error_code] = result["error_code"] || result[:error_code] if result["error_code"] || result[:error_code]
    out[:hint] = result["hint"] || result[:hint] if result["hint"] || result[:hint]
    return out
  end

  log = result["log"] || result[:log]
  out = { deploy_id: result["id"] || result[:id], status: result["status"] || result[:status] }
  out[:log_tail] = log.to_s.split("\n").last(50).join("\n") unless log.to_s.empty?
  out
end

def deploy_tarball(args)
  app_id = args["app_id"].to_s
  path = args["path"].to_s
  return { error: "app_id is required" } if app_id.empty?
  return { error: "path is required" } if path.empty?
  return { error: "path does not exist or is not a directory: #{path}" } unless Dir.exist?(path)

  warning = dirty_worktree_warning(path)

  result = Dir.mktmpdir("wokku-deploy") do |tmp|
    archive_path = File.join(tmp, "deploy.tar.gz")
    build_tarball!(path, archive_path)

    slot = api_request(:post, "/apps/#{app_id}/deploys/uploads")
    next slot if error_result?(slot)

    archive_key = slot["archive_key"]
    upload_url = slot["upload_url"]
    unless archive_key && upload_url
      next { error: "upload slot response missing archive_key/upload_url: #{slot.inspect}" }
    end

    upload_error = upload_tarball(upload_url, archive_path)
    next upload_error if upload_error

    deploy = api_request(:post, "/apps/#{app_id}/deploys", { archive_key: archive_key })
    next deploy if error_result?(deploy)

    deploy_id = deploy["deploy_id"]
    next({ error: "deploy response missing deploy_id: #{deploy.inspect}" }) unless deploy_id

    poll_deploy(app_id, deploy_id)
  end

  # Non-blocking: the deploy already happened (or already failed for its
  # own reasons) by the time we know about the dirty worktree, so we
  # thread the warning into whatever result — success or error — is about
  # to be returned, rather than gating on it.
  result = result.merge(warning: warning) if warning && result.is_a?(Hash)
  result
rescue => e
  # The rescue path must keep the dirty-worktree warning too — an archive
  # failure on a dirty tree is exactly when the user needs to see it.
  error = { error: "wokku_deploy_tarball failed: #{e.message}" }
  defined?(warning) && warning ? error.merge(warning: warning) : error
end

def handle_tool(name, args)
  case name
  when "wokku_doctor" then api_request(:get, "/doctor")
  when "wokku_list_servers" then api_request(:get, "/servers")
  when "wokku_get_server" then api_request(:get, "/servers/#{args['server_id']}")
  when "wokku_server_status" then api_request(:get, "/servers/#{args['server_id']}/status")
  when "wokku_list_apps" then api_request(:get, "/apps")
  when "wokku_get_app" then api_request(:get, "/apps/#{args['app_id']}")
  when "wokku_create_app"
    api_request(:post, "/apps", { name: args["name"], server_id: args["server_id"], deploy_branch: args["deploy_branch"] || "main" })
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
  when "wokku_deploy_tarball" then deploy_tarball(args)
  when "wokku_list_addons" then api_request(:get, "/apps/#{args['app_id']}/addons")
  when "wokku_add_addon" then api_request(:post, "/apps/#{args['app_id']}/addons", { service_type: args["service_type"], name: args["name"] })
  when "wokku_remove_addon" then api_request(:delete, "/apps/#{args['app_id']}/addons/#{args['addon_id']}")
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
  else
    { error: "Unknown tool: #{name}" }
  end
end

# Tool definitions — 57 tools, 100% coverage of Wokku API v1
TOOLS = [
  { name: "wokku_doctor", description: "Whole-chain self-diagnosis: auth, client version, host health, and app state in one call. Run this first when anything is failing or confusing, before digging into individual tools.", inputSchema: { type: "object", properties: {} } },
  { name: "wokku_list_servers", description: "List all connected servers", inputSchema: { type: "object", properties: {} } },
  { name: "wokku_get_server", description: "Get server details", inputSchema: { type: "object", properties: { server_id: { type: "string", description: "The server ID" } }, required: [ "server_id" ] } },
  { name: "wokku_server_status", description: "Get server health (CPU, memory, disk)", inputSchema: { type: "object", properties: { server_id: { type: "string", description: "The server ID" } }, required: [ "server_id" ] } },
  { name: "wokku_list_apps", description: "List all applications", inputSchema: { type: "object", properties: {} } },
  { name: "wokku_get_app", description: "Get app details", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID or name" } }, required: [ "app_id" ] } },
  { name: "wokku_create_app", description: "Create a new application", inputSchema: { type: "object", properties: { name: { type: "string", description: "App name" }, server_id: { type: "string", description: "Server ID (UUID)" }, deploy_branch: { type: "string", description: "Deploy branch (default: main)" } }, required: [ "name", "server_id" ] } },
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
  { name: "wokku_deploy_tarball", description: "Deploy an app from a local directory without a git remote: tars `path` (git archive when it's a git repo, else tar excluding .git/node_modules/tmp/log), uploads it, creates the deploy, and polls until it finishes. Returns the final status and a log tail.", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID or name" }, path: { type: "string", description: "Local directory to deploy" } }, required: [ "app_id", "path" ] } },
  { name: "wokku_list_addons", description: "List linked databases", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" } }, required: [ "app_id" ] } },
  { name: "wokku_add_addon", description: "Add a database to an app", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, service_type: { type: "string", description: "Database type" }, name: { type: "string", description: "Optional name" } }, required: [ "app_id", "service_type" ] } },
  { name: "wokku_remove_addon", description: "Remove a database from an app", inputSchema: { type: "object", properties: { app_id: { type: "string", description: "The app ID" }, addon_id: { type: "string", description: "The addon ID" } }, required: [ "app_id", "addon_id" ] } },
  { name: "wokku_list_templates", description: "List all templates", inputSchema: { type: "object", properties: {} } },
  { name: "wokku_get_template", description: "Get template details", inputSchema: { type: "object", properties: { template_id: { type: "string", description: "Template ID or slug" } }, required: [ "template_id" ] } },
  { name: "wokku_deploy_template", description: "Deploy a 1-click template", inputSchema: { type: "object", properties: { template_slug: { type: "string", description: "Template slug" }, server_id: { type: "string", description: "Server ID (UUID)" }, app_name: { type: "string", description: "App name" } }, required: [ "template_slug", "server_id" ] } },
  { name: "wokku_list_databases", description: "List all databases", inputSchema: { type: "object", properties: {} } },
  { name: "wokku_get_database", description: "Get database details", inputSchema: { type: "object", properties: { database_id: { type: "string", description: "The database ID" } }, required: [ "database_id" ] } },
  { name: "wokku_create_database", description: "Create a database", inputSchema: { type: "object", properties: { service_type: { type: "string", description: "Database type" }, name: { type: "string", description: "Name" }, server_id: { type: "string", description: "Server ID (UUID)" } }, required: [ "service_type", "name", "server_id" ] } },
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
  { name: "wokku_list_activities", description: "List recent activity log", inputSchema: { type: "object", properties: { limit: { type: "integer", description: "Number of entries (default: 20)" } } } }
].freeze

# Turns a tool result into the text shown to Claude. Plain {error: "msg"}
# bodies (old/self-hosted OSS servers, or the timeout/connection rescues in
# api_request above) render as a bare "error: msg" line, same as before.
# Typed error bodies — {error, error_code, hint, retryable} — additionally
# surface the code/hint/retryable so Claude can act on them (e.g. retry a
# deploy_lock_held error, or follow the hint) instead of just seeing a
# human sentence.
def format_result(result)
  return JSON.pretty_generate(result) unless result.is_a?(Hash)

  error = result["error"] || result[:error]
  return JSON.pretty_generate(result) unless error

  code = result["error_code"] || result[:error_code]
  hint = result["hint"] || result[:hint]
  retryable = result.key?("retryable") ? result["retryable"] : result[:retryable]

  text = code ? "error (#{code}): #{error}" : "error: #{error}"
  text += "\nhint: #{hint}" if hint
  text += "\nretryable: #{retryable}" unless retryable.nil?
  text
end

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
      $stdout.puts JSON.generate({ jsonrpc: "2.0", id: id, result: { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "wokku", version: SERVER_VERSION } } })
    when "notifications/initialized"
      # No response needed
    when "tools/list"
      $stdout.puts JSON.generate({ jsonrpc: "2.0", id: id, result: { tools: TOOLS } })
    when "tools/call"
      tool_name = msg.dig("params", "name")
      arguments = msg.dig("params", "arguments") || {}
      result = handle_tool(tool_name, arguments)
      $stdout.puts JSON.generate({ jsonrpc: "2.0", id: id, result: { content: [ { type: "text", text: format_result(result) } ] } })
    else
      $stdout.puts JSON.generate({ jsonrpc: "2.0", id: id, error: { code: -32601, message: "Method not found: #{msg['method']}" } })
    end
  rescue => e
    $stderr.puts "Error: #{e.message}"
  end
end
