# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

# Security assessment 2026-11-19, F-02: the MCP server must not silently
# adopt the CLI's saved login (a full-power token) — an agent gets only the
# token the user put in the plugin config.
class TokenSourceTest < Minitest::Test
  def setup
    @api = FakeApi.new
    @home = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@home, ".wokku"))
    File.write(File.join(@home, ".wokku", "config.json"), JSON.generate("token" => "cli-full-token"))
  end

  def teardown
    @mcp&.close
    @api.stop
    FileUtils.rm_rf(@home)
  end

  def test_ignores_the_cli_login_when_no_plugin_token
    @mcp = McpClient.new(api_url: "http://127.0.0.1:#{@api.port}/api/v1",
                         env: { "WOKKU_API_TOKEN" => "", "HOME" => @home })
    out = @mcp.call("wokku_list_apps")
    assert_includes out, "No Wokku token configured"
    assert_empty @api.requests, "must not call the API with the CLI's token"
  end

  def test_uses_the_plugin_token
    @mcp = McpClient.new(api_url: "http://127.0.0.1:#{@api.port}/api/v1", env: { "HOME" => @home })
    @mcp.call("wokku_list_apps")
    assert_equal "Bearer test-token", @api.requests.last[:headers]["authorization"]
  end
end
