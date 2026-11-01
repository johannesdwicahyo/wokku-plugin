# frozen_string_literal: true

require_relative "test_helper"

class ParityPhase1ToolsTest < Minitest::Test
  CASES = [
    [ "wokku_list_transfers", {}, "GET", "/api/v1/app_transfers" ],
    [ "wokku_accept_transfer", { "transfer_id" => "t1" }, "POST", "/api/v1/app_transfers/t1/accept" ],
    [ "wokku_decline_transfer", { "transfer_id" => "t1" }, "POST", "/api/v1/app_transfers/t1/decline" ],
    [ "wokku_cancel_transfer", { "transfer_id" => "t1" }, "DELETE", "/api/v1/app_transfers/t1" ],
    [ "wokku_update_team_member", { "team_id" => "T", "member_id" => "M", "role" => "viewer" }, "PATCH", "/api/v1/teams/T/members/M" ],
    [ "wokku_test_notification", { "notification_id" => "n1" }, "POST", "/api/v1/notifications/n1/test" ],
    [ "wokku_resize_database", { "database_id" => "pg", "cpu" => "0.5", "memory_mb" => 1024, "disk_gb" => 10 }, "PATCH", "/api/v1/databases/pg/resize" ],
    [ "wokku_retry_database", { "database_id" => "pg" }, "POST", "/api/v1/databases/pg/retry" ],
    [ "wokku_list_invoices", {}, "GET", "/api/v1/billing/invoices" ]
  ].freeze

  def setup
    @api = FakeApi.new
    @mcp = McpClient.new(api_url: "http://127.0.0.1:#{@api.port}/api/v1")
  end

  def teardown
    @mcp.close
    @api.stop
  end

  CASES.each_with_index do |(tool, args, verb, path), i|
    define_method("test_#{i}_#{tool}") do
      @mcp.call(tool, args)
      req = @api.requests.last
      refute_nil req, "#{tool} made no request"
      assert_equal verb, req[:method]
      assert_equal path, req[:path].split("?").first
    end
  end

  def test_role_body
    @mcp.call("wokku_update_team_member", { "team_id" => "T", "member_id" => "M", "role" => "viewer" })
    assert_equal({ "role" => "viewer" }, JSON.parse(@api.requests.last[:body]))
  end

  def test_resize_body
    @mcp.call("wokku_resize_database", { "database_id" => "pg", "cpu" => "0.5", "memory_mb" => 1024, "disk_gb" => 10 })
    assert_equal({ "cpu" => "0.5", "memory_mb" => 1024, "disk_gb" => 10 }, JSON.parse(@api.requests.last[:body]))
  end
end
