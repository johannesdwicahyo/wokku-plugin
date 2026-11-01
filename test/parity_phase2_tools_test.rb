# frozen_string_literal: true

require_relative "test_helper"

class ParityPhase2ToolsTest < Minitest::Test
  def setup
    @api = FakeApi.new
    @mcp = McpClient.new(api_url: "http://127.0.0.1:#{@api.port}/api/v1")
  end

  def teardown
    @mcp.close
    @api.stop
  end

  def test_preview_settings
    @mcp.call("wokku_set_preview_settings", { "app_id" => "shop", "preview_enabled" => true, "database_strategy" => "snapshot" })
    req = @api.requests.last
    assert_equal [ "PATCH", "/api/v1/apps/shop/preview_settings" ], [ req[:method], req[:path] ]
    assert_equal({ "preview_enabled" => true, "database_strategy" => "snapshot" }, JSON.parse(req[:body]))
  end

  def test_github_repos
    @mcp.call("wokku_list_github_repos", {})
    assert_equal "/api/v1/github/repos", @api.requests.last[:path]
  end

  def test_github_repo_branches
    @mcp.call("wokku_list_github_repos", { "repo" => "acme/shop" })
    assert_equal "/api/v1/github/repos?repo=acme%2Fshop", @api.requests.last[:path]
  end

  def test_rotate_vitals_token
    @mcp.call("wokku_rotate_vitals_token", { "app_id" => "shop" })
    req = @api.requests.last
    assert_equal [ "POST", "/api/v1/apps/shop/vitals/rotate_token" ], [ req[:method], req[:path] ]
  end
end
