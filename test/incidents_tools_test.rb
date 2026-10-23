# frozen_string_literal: true

require_relative "test_helper"

class IncidentsToolsTest < Minitest::Test
  CASES = [
    [ "wokku_list_incidents", {}, "GET", "/api/v1/incidents", "state=open" ],
    [ "wokku_list_incidents", { "state" => "all", "app_id" => "web" }, "GET", "/api/v1/incidents", "state=all&app_id=web" ],
    [ "wokku_get_incident", { "incident_id" => "i1" }, "GET", "/api/v1/incidents/i1", nil ],
    [ "wokku_list_alert_mutes", {}, "GET", "/api/v1/alert_mutes", nil ],
    [ "wokku_mute_alerts", { "app_id" => "web", "event" => "app_down", "until" => "2026-10-24T00:00:00Z" }, "POST", "/api/v1/alert_mutes", nil ],
    [ "wokku_unmute_alerts", { "mute_id" => "m1" }, "DELETE", "/api/v1/alert_mutes/m1", nil ]
  ].freeze

  def setup
    @api = FakeApi.new
    @mcp = McpClient.new(api_url: "http://127.0.0.1:#{@api.port}/api/v1")
  end

  def teardown
    @mcp.close
    @api.stop
  end

  CASES.each_with_index do |(tool, args, verb, path, query), i|
    define_method("test_#{i}_#{tool}") do
      @mcp.call(tool, args)
      req = @api.requests.last
      refute_nil req, "#{tool} made no request"
      assert_equal verb, req[:method]
      assert_equal path, req[:path].split("?").first
      assert_equal query, req[:path].split("?", 2)[1] if query
    end
  end

  def test_mute_body
    @mcp.call("wokku_mute_alerts", { "event" => "app_down" })
    assert_equal({ "event" => "app_down" }, JSON.parse(@api.requests.last[:body]))
  end
end
