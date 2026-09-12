#!/usr/bin/env ruby
# Local publication/packaging checks. No GitHub calls or signing credentials.
require 'fileutils'
require 'json'
require 'open3'
require 'tmpdir'
require 'yaml'

# The harness doubles as fake tools so publication cannot reach GitHub.
case File.basename($PROGRAM_NAME)
when 'gh'
  File.open(ENV.fetch('RELEASE_TEST_CALLS'), 'a') { |file| file.puts(JSON.generate(ARGV)) }
  exit 1 if ENV['RELEASE_TEST_API_FAILURE'] == '1' && ARGV.first == 'api'
  puts 'refs/tags/existing' if ENV['RELEASE_TEST_EXISTING'] == '1' && ARGV.first == 'api'
  exit 1 if ENV['RELEASE_TEST_CREATE_FAILURE'] == '1' && ARGV.first == 'release'
  exit 0
when 'date'
  abort 'expected one UTC timestamp' unless ARGV == ['-u', '+%Y%m%d_%H%M%S']
  puts '20260912_201500'
  exit 0
end

ROOT = File.expand_path('..', __dir__)
BASH = ARGV.fetch(0, '/bin/bash')

def check(condition, message)
  raise message unless condition
end

def run_script(name, args, env = {}, success: true)
  output, status = Open3.capture2e(env, BASH, File.join(ROOT, '_scripts', name), *args)
  check(status.success? == success, "#{name}: unexpected exit #{status.exitstatus}\n#{output}")
  output
end

# Check gates, artifact dependencies, and credential boundaries in the actual YAML.
%w[build release].each do |workflow|
  config = YAML.load_file(File.join(ROOT, '.github/workflows', "#{workflow}.yml"))
  jobs = config.fetch('jobs')
  publisher = jobs.fetch(workflow == 'build' ? 'pre-release' : 'publish')
  check(config.fetch('permissions') == { 'contents' => 'read' }, 'default token must be read-only')
  check(publisher.fetch('needs') == workflow, 'publication must depend on the successful build')
  check(publisher.fetch('if').include?("github.event_name == 'push'"), 'PR publication must be disabled')
  check(publisher.fetch('permissions') == { 'contents' => 'write' }, 'publisher needs contents write')
  check(jobs.fetch(workflow).fetch('steps').none? { |step| step['run'].to_s.include?('test-sign-release') }, 'signing tests must stay outside CI')
  check(jobs.fetch(workflow).fetch('steps').any? { |step| step['uses'] == './.github/actions/build-release' }, 'release builds must use the shared action')
end

Dir.mktmpdir('superscribe-release-tests.') do |temp|
  tools = File.join(temp, 'tools')
  FileUtils.mkdir_p(tools)
  %w[gh date].each do |tool|
    wrapper = File.join(tools, tool)
    # Invoke through a symlink so the harness identifies the fake command.
    FileUtils.ln_s(File.expand_path(__FILE__), wrapper)
  end
  calls = File.join(temp, 'calls.jsonl')
  env = {
    'PATH' => "#{tools}:#{ENV.fetch('PATH')}",
    'RELEASE_TEST_CALLS' => calls,
    'GH_TOKEN' => 'test-only',
    'GITHUB_EVENT_NAME' => 'push',
    'GITHUB_REPOSITORY' => 'test/superscribe',
    'GITHUB_SHA' => 'a' * 40,
    'GITHUB_RUN_NUMBER' => '42'
  }
  assets = File.join(temp, 'unsigned')
  FileUtils.mkdir(assets)
  binary = File.join(assets, 'superscribe')
  FileUtils.cp('/usr/bin/true', binary)
  FileUtils.chmod(0755, binary)

  publish = lambda do |ref, success = true, overrides = {}, directory = assets, version = '1.0.7'|
    File.write(calls, '')
    run_script('publish-release.sh', [version, directory], env.merge('GITHUB_REF' => ref).merge(overrides), success: success)
    File.readlines(calls).map { |line| JSON.parse(line) }
  end

  %w[develop feature/audio feature/nested/audio].each do |branch|
    commands = publish.call("refs/heads/#{branch}")
    create = commands.last
    check(create[0..2] == ['release', 'create', 'R1.0.7_BUILD_42_20260912_201500'], 'incorrect pre-release tag')
    check(create[create.index('--title') + 1] == 'superscribe-build-42-20260912-201500', 'incorrect pre-release title')
    check(create[create.index('--target') + 1] == 'a' * 40, 'must target tested SHA')
    check(create.include?('--prerelease') && create.include?('--latest=false'), 'incorrect pre-release flags')
    check(create.include?(binary), 'pre-release must include raw binary')
  end

  %w[refs/heads/main refs/heads/develop refs/heads/feature/audio].each do |ref|
    check(publish.call(ref, false, { 'GITHUB_EVENT_NAME' => 'pull_request' }).empty?, 'PR must not call GitHub')
  end
  %w[refs/heads/other refs/tags/v1.0.7 refs/heads/feature/].each do |ref|
    check(publish.call(ref, false).empty?, 'ineligible ref must not call GitHub')
  end
  check(publish.call('refs/heads/develop', false, {}, assets, '../bad').empty?, 'invalid version must not call GitHub')
  check(publish.call('refs/heads/develop', false, { 'GITHUB_SHA' => 'develop' }).empty?, 'branch target must be rejected')
  %w[RELEASE_TEST_API_FAILURE RELEASE_TEST_EXISTING].each do |failure|
    commands = publish.call('refs/heads/develop', false, { failure => '1' })
    check(commands.length == 1 && commands.first.first == 'api', 'API error or existing tag must prevent publication')
  end
  publish.call('refs/heads/develop', false, { 'RELEASE_TEST_CREATE_FAILURE' => '1' })

  dist = File.join(temp, 'dist')
  run_script('package-release.sh', ['1.0.7', binary, dist])
  archive = File.join(dist, 'superscribe-1.0.7-macos-arm64.tar.gz')
  listing, status = Open3.capture2e('tar', '-tzf', archive)
  expected = ['superscribe-1.0.7-macos-arm64/', 'superscribe-1.0.7-macos-arm64/superscribe', 'superscribe-1.0.7-macos-arm64/README.md', 'superscribe-1.0.7-macos-arm64/LICENSE']
  check(status.success? && listing.lines.map(&:strip).sort == expected.sort, 'incorrect archive layout')
  extracted = File.join(temp, 'extracted')
  FileUtils.mkdir(extracted)
  _, status = Open3.capture2e('tar', '-xzf', archive, '-C', extracted)
  extracted_binary = File.join(extracted, 'superscribe-1.0.7-macos-arm64/superscribe')
  check(status.success? && File.executable?(extracted_binary) && FileUtils.compare_file(binary, extracted_binary), 'packaging must preserve executable bytes and permissions')
  check(Dir.children(dist).sort == ['SHA256SUMS.txt', File.basename(archive)].sort, 'packaging left staging files')
  run_script('package-release.sh', ['1.0.7', binary, dist], {}, success: false)
  run_script('package-release.sh', ['1.0.7', File.join(temp, 'missing'), File.join(temp, 'missing-output')], {}, success: false)

  commands = publish.call('refs/heads/main', true, {}, dist)
  create = commands.last
  check(create[0..2] == ['release', 'create', 'v1.0.7'], 'incorrect stable tag')
  check(create[create.index('--title') + 1] == 'v1.0.7', 'incorrect stable title')
  check(create[create.index('--target') + 1] == 'a' * 40, 'stable tag must target tested SHA')
  check(!create.include?('--prerelease') && create.include?(archive) && create.include?(File.join(dist, 'SHA256SUMS.txt')), 'incorrect stable assets or flags')
  check(publish.call('refs/heads/main', false, { 'RELEASE_TEST_EXISTING' => '1' }, dist).length == 1, 'stable tags must not be replaced')
  File.open(archive, 'a') { |file| file.write('tampered') }
  check(publish.call('refs/heads/main', false, {}, dist).empty?, 'checksum mismatch must prevent publication')
  FileUtils.rm(binary)
  check(publish.call('refs/heads/develop', false).empty?, 'missing binary must prevent publication')
end

puts "Release workflow, packaging, and publication checks passed (#{BASH})."
