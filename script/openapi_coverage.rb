#!/usr/bin/env ruby
# frozen_string_literal: true
# Compares API calls found in source against the Wokku OpenAPI contract.
# Calls are `api(:verb, "/path")` (CLI), `api_request(:verb, "/path")` (MCP),
# `api_upload(:post, "/path")` (raw-body uploads), `<client>.stream(:verb, "/path")`,
# `poll_until("/path")` (always GET) and `post_json(url, "/path")` /
# `post_raw(url, "/path")` (CLI device-flow login, always POST);
# paths relative to /api/v1; "#{...}" segments match any {param}.
# Skips `deprecated: true` operations (retired 410 endpoints). A `<res>.replace`
# (PUT) counts as covered when its `<res>.update` (PATCH) twin is, and vice versa.
# Known blind spot: paths built in a variable first (e.g. CLI shell.rb resource_path).
#
#   ruby script/openapi_coverage.rb CONTRACT GLOB [--gate]
#   --gate: exit 1 on any uncovered, non-ignored operation or stale ignore entry.
require "yaml"
require "open-uri"

CALL = /\b(?:api|api_request|api_upload|stream)\(:(get|post|put|patch|delete),\s*"([^"]+)"/
POLL = /\bpoll_until\(\s*"([^"]+)"/
POST_URL = /\bpost_(?:json|raw)\(\s*\w+,\s*"([^"]+)"/

# => [[verb, path, operationId, deprecated?], ...]
def contract_ops(src)
  raw = src.start_with?("http") ? URI.open(src).read : File.read(src)
  YAML.safe_load(raw, aliases: true).fetch("paths").flat_map do |path, ops|
    ops.filter_map do |verb, op|
      [ verb, path.delete_prefix("/api/v1"), op["operationId"], op["deprecated"] == true ] if op.is_a?(Hash)
    end
  end
end

def scan_calls(text)
  text.scan(CALL) + text.scan(POLL).map { |(p)| [ "get", p ] } + text.scan(POST_URL).map { |(p)| [ "post", p ] }
end

def source_calls(files)
  files.flat_map { |f| scan_calls(File.read(f)) }.map { |v, p| [ v, p.split("?").first ] }.uniq
end

def matches?(template, call)
  re = Regexp.new("\\A" + Regexp.escape(template).gsub(/\\\{[^}]+\\\}/, "[^/]+") + "\\z")
  re.match?(call.gsub(/#\{[^}]+\}/, "x"))
end

def twin(id)
  return id.sub(/\.replace\z/, ".update") if id.end_with?(".replace")
  return id.sub(/\.update\z/, ".replace") if id.end_with?(".update")
  nil
end

def uncovered(ops, calls, ignore)
  live = ops.reject { |o| o[3] }
  hit = live.select { |verb, path, _| calls.any? { |v, p| v == verb && matches?(path, p) } }.map { |o| o[2] }
  live.reject { |_, _, id, _| ignore.include?(id) || hit.include?(id) || hit.include?(twin(id)) }
end

def stale_ignores(ops, ignore)
  ignore - ops.map { |o| o[2] }
end

def load_ignore(file = "openapi-coverage.yml")
  return [] unless File.exist?(file)
  Array(YAML.safe_load_file(file)&.fetch("ignore", nil)).map { |e| e.is_a?(Hash) ? e.fetch("id") : e.to_s }
end

if ARGV.first == "--self-test"
  ops = [ [ "get", "/apps/{id}", "apps.show", false ], [ "post", "/apps/{id}/restart", "apps.restart", false ],
          [ "get", "/meta", "meta.show", false ], [ "get", "/apps/{id}/logs", "logs.show", false ],
          [ "get", "/apps/{id}/addons", "addons.list", false ], [ "get", "/x", "x.show", false ] ]
  calls = source_calls([]) + [ [ "get", "/apps/\#{app_id}" ] ]
  left = uncovered(ops, calls, [ "meta.show" ]).map { |o| o[2] }
  raise "self-test failed: #{left.inspect}" unless left == %w[apps.restart logs.show addons.list x.show]
  # stream(...) with query string, and poll_until(path) as GET
  src = 'Wokku.api_client.stream(:get, "/apps/#{id}/logs?follow=1") { }; poll_until("/apps/#{id}/addons", attempts: 1)'
  found = scan_calls(src).map { |v, p| [ v, p.split("?").first ] }
  left = uncovered(ops, found, [ "meta.show" ]).map { |o| o[2] }
  raise "self-test (stream/poll_until) failed: #{left.inspect}" unless left == %w[apps.show apps.restart x.show]
  # deprecated skipped; PUT/PATCH twins; api_upload; post_json/post_raw
  ops2 = [ [ "get", "/old", "old.show", true ], [ "patch", "/apps/{id}", "apps.update", false ],
           [ "put", "/apps/{id}", "apps.replace", false ], [ "post", "/databases/{id}/import", "databases.import", false ],
           [ "post", "/auth/device/code", "auth_devices.code", false ], [ "post", "/auth/device/token", "auth_devices.token", false ] ]
  src2 = 'api(:put, "/apps/#{id}", {}); api_upload(:post, "/databases/#{db}/import", f); ' \
         'post_json(url, "/auth/device/code", {}); post_raw(url, "/auth/device/token", {})'
  left = uncovered(ops2, scan_calls(src2), [])
  raise "self-test (deprecated/twin/upload/post_url) failed: #{left.inspect}" unless left.empty?
  # stale ignore entries are reported
  stale = stale_ignores(ops2, [ "apps.update", "gone.op" ])
  raise "self-test (stale) failed: #{stale.inspect}" unless stale == [ "gone.op" ]
  puts "self-test ok"
  exit 0
end

gate = ARGV.delete("--gate") || ARGV.delete("--strict")
contract, glob = ARGV
abort "usage: openapi_coverage.rb CONTRACT GLOB [--gate] | --self-test" unless contract && glob
ignore = load_ignore
ops = contract_ops(contract)
live = ops.reject { |o| o[3] }
left = uncovered(ops, source_calls(Dir.glob(glob)), ignore)
stale = stale_ignores(ops, ignore)
puts "covered #{live.size - left.size - (ignore & live.map { |o| o[2] }).size}/#{live.size} (#{ignore.size} ignored, #{ops.size - live.size} retired)"
left.each { |o| puts "  uncovered: #{o[2]}" }
stale.each { |id| puts "  stale ignore: #{id}" }
exit(gate && (left.any? || stale.any?) ? 1 : 0)
