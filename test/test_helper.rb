# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "open3"
require "socket"

SERVER = File.expand_path("../plugins/wokku/mcp/server.rb", __dir__)

# Minimal HTTP/1.1 server on a random port: records each request and answers
# from a canned table. Stdlib only (the plugin ships with no gems).
class FakeApi
  attr_reader :requests, :port

  def initialize(responses = {})
    @responses = responses
    @requests = []
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new { loop { handle(@server.accept) } }
  end

  def stop
    @thread.kill
    @server.close
  end

  private

  def handle(sock)
    line = sock.gets or return sock.close
    verb, target, = line.split(" ")
    headers = {}
    while (h = sock.gets) && h != "\r\n"
      k, v = h.split(":", 2)
      headers[k.strip.downcase] = v.to_s.strip
    end
    body = headers["content-length"] ? sock.read(headers["content-length"].to_i) : nil
    path = target.split("?").first
    @requests << { method: verb, path: target, body: body, headers: headers }
    status, payload = @responses.fetch("#{verb} #{path}", [ 200, {} ])
    json = JSON.generate(payload)
    sock.write "HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{json.bytesize}\r\nConnection: close\r\n\r\n#{json}"
    sock.close
  rescue IOError, Errno::EPIPE, Errno::ECONNRESET
    nil
  end
end

# Drives server.rb over stdio JSON-RPC, as Claude Code does.
class McpClient
  def initialize(api_url:)
    env = { "WOKKU_API_URL" => api_url, "WOKKU_API_TOKEN" => "test-token" }
    @stdin, @stdout, @stderr, @wait = Open3.popen3(env, "ruby", SERVER)
    @id = 0
    rpc("initialize", {})
  end

  def tools = rpc("tools/list", {}).dig("result", "tools")

  def call(name, args = {})
    rpc("tools/call", { name: name, arguments: args }).dig("result", "content", 0, "text")
  end

  def close
    @stdin.close
    @wait.value
  end

  private

  def rpc(method, params)
    @id += 1
    @stdin.puts JSON.generate({ jsonrpc: "2.0", id: @id, method: method, params: params })
    @stdin.flush
    JSON.parse(@stdout.gets)
  end
end
