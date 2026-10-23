# frozen_string_literal: true

require_relative "test_helper"

class RestoredToolsTest < Minitest::Test
  CASES = [
    [ "wokku_rename_app", { "app_id" => "a", "new_name" => "b" }, "PATCH", "/api/v1/apps/a/rename", { "name" => "b" } ],
    [ "wokku_clone_app", { "app_id" => "a", "new_name" => "b" }, "POST", "/api/v1/apps/a/clone", { "name" => "b", "skip_deploy" => true } ],
    [ "wokku_transfer_app", { "app_id" => "a", "recipient_email" => "x@y.z" }, "POST", "/api/v1/apps/a/transfer", { "recipient_email" => "x@y.z" } ],
    [ "wokku_lock_app", { "app_id" => "a" }, "POST", "/api/v1/apps/a/lock", nil ],
    [ "wokku_unlock_app", { "app_id" => "a" }, "POST", "/api/v1/apps/a/unlock", nil ],
    [ "wokku_set_https", { "app_id" => "a", "enabled" => false }, "PATCH", "/api/v1/apps/a/https", { "enabled" => false } ],
    [ "wokku_set_cdn", { "app_id" => "a", "enabled" => true }, "PATCH", "/api/v1/apps/a/cdn", { "enabled" => true } ],
    [ "wokku_set_maintenance", { "app_id" => "a", "enabled" => true }, "PATCH", "/api/v1/apps/a/maintenance", { "enabled" => true } ],
    [ "wokku_github_connect", { "app_id" => "a", "repo" => "o/r" }, "POST", "/api/v1/apps/a/github_connect", { "repo" => "o/r", "branch" => "main" } ],
    [ "wokku_github_disconnect", { "app_id" => "a" }, "DELETE", "/api/v1/apps/a/github_disconnect", nil ],
    [ "wokku_list_previews", { "app_id" => "a" }, "GET", "/api/v1/apps/a/previews", nil ],
    [ "wokku_destroy_preview", { "app_id" => "a", "pr_number" => 42 }, "DELETE", "/api/v1/apps/a/previews/42", nil ],
    [ "wokku_list_scheduled_tasks", { "app_id" => "a" }, "GET", "/api/v1/apps/a/scheduled_tasks", nil ],
    [ "wokku_create_scheduled_task", { "app_id" => "a", "command" => "rake x", "schedule" => "0 * * * *" }, "POST", "/api/v1/apps/a/scheduled_tasks", { "command" => "rake x", "schedule" => "0 * * * *" } ],
    [ "wokku_delete_scheduled_task", { "app_id" => "a", "task_id" => "t1" }, "DELETE", "/api/v1/apps/a/scheduled_tasks/t1", nil ],
    [ "wokku_get_app_metrics", { "app_id" => "a" }, "GET", "/api/v1/apps/a/metrics", nil ],
    [ "wokku_get_app_monitor", { "app_id" => "a" }, "GET", "/api/v1/apps/a/monitor", nil ],
    [ "wokku_get_app_vitals", { "app_id" => "a" }, "GET", "/api/v1/apps/a/vitals", nil ],
    [ "wokku_get_database_monitor", { "database_id" => "d" }, "GET", "/api/v1/databases/d/monitor", nil ],
    [ "wokku_get_current_plan", {}, "GET", "/api/v1/billing/current_plan", nil ]
  ].freeze

  def setup
    @api = FakeApi.new
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
      actual = (req[:body] && JSON.parse(req[:body]))
      if body.nil?
        assert_nil actual
      else
        assert_equal body, actual
      end
    end
  end
end
