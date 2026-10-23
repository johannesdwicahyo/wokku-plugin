# frozen_string_literal: true

require_relative "test_helper"

class ToolsTest < Minitest::Test
  def setup
    @api = FakeApi.new
    @mcp = McpClient.new(api_url: "http://127.0.0.1:#{@api.port}/api/v1")
  end

  def teardown
    @mcp.close
    @api.stop
  end

  # v1.3.0 silently dropped 25 tools; listed and dispatched names must match.
  def test_every_listed_tool_is_dispatched_and_vice_versa
    listed = @mcp.tools.map { |t| t["name"] }.sort
    dispatched = File.read(SERVER).scan(/when "(wokku_[a-z_]+)"/).flatten.uniq.sort
    assert_equal dispatched, listed
    assert_equal listed.uniq, listed, "duplicate tool names"
  end

  def test_every_tool_has_description_and_valid_schema
    @mcp.tools.each do |t|
      refute_empty t["description"].to_s, "#{t['name']} has no description"
      schema = t["inputSchema"]
      assert_equal "object", schema["type"], t["name"]
      missing = Array(schema["required"]) - schema.fetch("properties", {}).keys
      assert_empty missing, "#{t['name']} requires undeclared #{missing}"
    end
  end

  def test_restart_sends_post_with_auth
    @mcp.call("wokku_restart_app", { "app_id" => "my-app" })
    req = @api.requests.last
    assert_equal [ "POST", "/api/v1/apps/my-app/restart" ], [ req[:method], req[:path] ]
    assert_equal "Bearer test-token", req[:headers]["authorization"]
  end
end
