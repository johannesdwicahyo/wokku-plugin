#!/usr/bin/env ruby
# frozen_string_literal: true
# Compares API calls found in source against the Wokku OpenAPI contract.
# Calls are `api(:verb, "/path")` (CLI), `api_request(:verb, "/path")` (MCP),
# `<client>.stream(:verb, "/path")` and `poll_until("/path")` (always GET);
# paths relative to /api/v1; "#{...}" segments match any {param}.
# Known blind spot: paths built in a variable first (e.g. CLI shell.rb resource_path).
require "yaml"
require "open-uri"

CALL = /\b(?:api|api_request|stream)\(:(get|post|put|patch|delete),\s*"([^"]+)"/
POLL = /\bpoll_until\(\s*"([^"]+)"/

def contract_ops(src)
  raw = src.start_with?("http") ? URI.open(src).read : File.read(src)
  YAML.safe_load(raw, aliases: true).fetch("paths").flat_map do |path, ops|
    ops.filter_map { |verb, op| [ verb, path.delete_prefix("/api/v1"), op["operationId"] ] if op.is_a?(Hash) }
  end
end

def scan_calls(text)
  text.scan(CALL) + text.scan(POLL).map { |(p)| [ "get", p ] }
end

def source_calls(files)
  files.flat_map { |f| scan_calls(File.read(f)) }.map { |v, p| [ v, p.split("?").first ] }.uniq
end

def matches?(template, call)
  re = Regexp.new("\\A" + Regexp.escape(template).gsub(/\\\{[^}]+\\\}/, "[^/]+") + "\\z")
  re.match?(call.gsub(/#\{[^}]+\}/, "x"))
end

def uncovered(ops, calls, ignore)
  ops.reject { |verb, path, id| ignore.include?(id) || calls.any? { |v, p| v == verb && matches?(path, p) } }
end

if ARGV.first == "--self-test"
  ops = [ [ "get", "/apps/{id}", "apps.show" ], [ "post", "/apps/{id}/restart", "apps.restart" ], [ "get", "/meta", "meta.show" ],
          [ "get", "/apps/{id}/logs", "logs.show" ], [ "get", "/apps/{id}/addons", "addons.list" ], [ "get", "/x", "x.show" ] ]
  calls = source_calls([]) + [ [ "get", "/apps/\#{app_id}" ] ]
  left = uncovered(ops, calls, [ "meta.show" ]).map(&:last)
  raise "self-test failed: #{left.inspect}" unless left == %w[apps.restart logs.show addons.list x.show]
  # extensions: stream(...) with query string, and poll_until(path) as GET
  src = 'Wokku.api_client.stream(:get, "/apps/#{id}/logs?follow=1") { }; poll_until("/apps/#{id}/addons", attempts: 1)'
  found = scan_calls(src).map { |v, p| [ v, p.split("?").first ] }
  left = uncovered(ops, found, [ "meta.show" ]).map(&:last)
  raise "self-test (stream/poll_until) failed: #{left.inspect}" unless left == %w[apps.show apps.restart x.show]
  puts "self-test ok"
  exit 0
end

contract, glob, strict = ARGV[0], ARGV[1], ARGV.include?("--strict")
ignore = File.exist?("openapi-coverage.yml") ? Array(YAML.safe_load_file("openapi-coverage.yml")&.fetch("ignore", [])) : []
ops = contract_ops(contract)
left = uncovered(ops, source_calls(Dir.glob(glob)), ignore)
puts "covered #{ops.size - left.size}/#{ops.size}"
left.each { |_, _, id| puts "  uncovered: #{id}" }
exit(strict && left.any? ? 1 : 0)
