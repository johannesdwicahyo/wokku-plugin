# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"

class NewToolsTest < Minitest::Test
  CASES = [
    [ "wokku_whoami", {}, "GET", "/api/v1/auth/whoami", nil ],
    [ "wokku_list_api_tokens", {}, "GET", "/api/v1/auth/tokens", nil ],
    [ "wokku_create_api_token", { "name" => "ci" }, "POST", "/api/v1/auth/tokens", { "name" => "ci" } ],
    [ "wokku_revoke_api_token", { "token_id" => "t1" }, "DELETE", "/api/v1/auth/tokens/t1", nil ],
    [ "wokku_ai_diagnose", { "deploy_id" => "d1" }, "POST", "/api/v1/ai/diagnose", { "deploy_id" => "d1" } ],
    [ "wokku_get_run", { "app_id" => "a", "run_id" => "r1" }, "GET", "/api/v1/apps/a/runs/r1", nil ],
    [ "wokku_list_box_sizes", {}, "GET", "/api/v1/dyno_tiers", nil ],
    [ "wokku_get_dynos", { "app_id" => "a" }, "GET", "/api/v1/apps/a/dynos", nil ],
    [ "wokku_resize_app", { "app_id" => "a", "dyno_id" => "y1", "box_size" => "standard" }, "PATCH", "/api/v1/apps/a/dynos/y1", { "dyno_tier_name" => "standard" } ],
    [ "wokku_get_backup_download_url", { "database_id" => "d", "backup_id" => "b" }, "GET", "/api/v1/databases/d/backups/b/download", nil ],
    [ "wokku_restore_backup", { "database_id" => "d", "backup_id" => "b" }, "POST", "/api/v1/databases/d/backups/b/restore", nil ],
    [ "wokku_scale_app", { "app_id" => "a", "scaling" => { "clock" => 1 } }, "PUT", "/api/v1/apps/a/ps", { "scaling" => { "clock" => 1 } } ]
  ].freeze

  def setup
    @api = FakeApi.new(
      "POST /api/v1/apps/a/run" => [ 202, { run_id: "r9" } ],
      "GET /api/v1/apps/a/runs/r9" => [ 200, { run_id: "r9", status: "succeeded", exit_code: 0, output: "hello" } ]
    )
    @mcp = McpClient.new(api_url: "http://127.0.0.1:#{@api.port}/api/v1")
  end

  def teardown
    @mcp.close
    @api.stop
  end

  CASES.each do |tool, args, verb, path, body|
    define_method("test_#{tool}") do
      @mcp.call(tool, args)
      req = @api.requests.last
      refute_nil req, "#{tool} made no request"
      assert_equal [ verb, path ], [ req[:method], req[:path] ]
      actual = req[:body] && JSON.parse(req[:body])
      body.nil? ? assert_nil(actual) : assert_equal(body, actual)
    end
  end

  def test_scale_app_keeps_web_worker_shorthand
    @mcp.call("wokku_scale_app", { "app_id" => "a", "web" => 2 })
    assert_equal({ "scaling" => { "web" => 2 } }, JSON.parse(@api.requests.last[:body]))
  end

  # Review focus 1: run is async (202 + run_id); the tool must poll to a result.
  def test_run_command_polls_until_terminal
    text = @mcp.call("wokku_run_command", { "app_id" => "a", "command" => "echo hello" })
    paths = @api.requests.map { |r| "#{r[:method]} #{r[:path]}" }
    assert_equal [ "POST /api/v1/apps/a/run", "GET /api/v1/apps/a/runs/r9" ], paths
    assert_equal({ "command" => "echo hello" }, JSON.parse(@api.requests.first[:body]))
    assert_includes text, "hello"
    assert_includes text, "succeeded"
  end

  # Review focus 2: import streams the raw file, not JSON.
  def test_import_database_streams_raw_file
    Tempfile.create("dump") do |f|
      f.binmode
      f.write("PGDMP\x00\x01binary")
      f.flush
      @mcp.call("wokku_import_database", { "database_id" => "d", "file_path" => f.path })
      req = @api.requests.last
      assert_equal [ "POST", "/api/v1/databases/d/import" ], [ req[:method], req[:path] ]
      assert_equal "application/octet-stream", req[:headers]["content-type"]
      assert_equal "PGDMP\x00\x01binary".b, req[:body].b
    end
  end

  def test_import_database_rejects_missing_file
    text = @mcp.call("wokku_import_database", { "database_id" => "d", "file_path" => "/nope/missing.dump" })
    assert_includes text, "not found"
    assert_empty @api.requests
  end
end
