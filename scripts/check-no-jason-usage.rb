#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"

ROOT = Pathname.new(__dir__).join("..").expand_path

SCAN_GLOBS = [
  "app/config/**/*.{ex,exs}",
  "app/lib/**/*.{ex,exs}",
  "app/test/**/*.{ex,exs}",
  "app/mix.exs"
].freeze

EXCLUDED_PREFIXES = [
  "app/_build/",
  "app/deps/"
].freeze

PATTERNS = {
  "Jason module" => /\bJason\b/,
  "Jason dependency atom" => /:jason\b/,
  "Jason dependency string" => /["']jason["']/
}.freeze

def source_files
  SCAN_GLOBS
    .flat_map { |glob| Dir[ROOT.join(glob).to_s] }
    .map { |path| Pathname.new(path).relative_path_from(ROOT).to_s }
    .reject { |path| EXCLUDED_PREFIXES.any? { |prefix| path.start_with?(prefix) } }
    .sort
end

violations = []

source_files.each do |path|
  ROOT.join(path).read.each_line.with_index(1) do |line, line_number|
    PATTERNS.each do |name, pattern|
      next unless line.match?(pattern)

      violations << [path, line_number, name, line.strip]
    end
  end
end

if violations.any?
  warn "Wardwright app code must use Elixir's JSON module, not Jason."
  warn "Transitive dependencies may still depend on Jason, but app-owned code must not call or declare it."

  violations.each do |path, line_number, name, line|
    warn "#{path}:#{line_number}: #{name}: #{line}"
  end

  abort("Jason usage ratchet failed")
end

puts "Jason usage ratchet passed"
