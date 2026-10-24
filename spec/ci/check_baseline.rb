require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'time'

CHECKOUT = '/checkout'.freeze
RESULTS = '/results'.freeze
COPY_PATHS = %w[Gemfile Gemfile.lock .ruby-version .rspec spec fs_overlay].freeze

def git(*args)
  output, error, status = Open3.capture3('git', '-C', CHECKOUT, *args)
  raise "Git inspection failed: #{error.gsub(CHECKOUT, '<checkout>')}" unless status.success?
  output.strip
end

def manifest(directory)
  paths = %w[Gemfile Gemfile.lock .ruby-version .rspec dev/check_p1.rb]
  %w[spec fs_overlay].each do |name|
    Dir.glob(File.join(directory, name, '**', '*'), File::FNM_DOTMATCH).each do |path|
      next unless File.file?(path)
      relative = path.delete_prefix(directory + '/')
      next if relative == 'spec/examples.txt'
      paths << relative
    end
  end
  paths.sort.uniq.map do |path|
    "#{Digest::SHA256.file(File.join(directory, path)).hexdigest}  #{path}"
  end
end

def fingerprint(lines)
  Digest::SHA256.hexdigest(lines.join("\n"))
end

metadata = { startedUtc: Time.now.utc.iso8601, result: 'running', stage: 'baseline' }
metadata_path = File.join(RESULTS, 'baseline.json')
git_home = nil
begin
  raise 'Expected Ruby 2.7.2' unless RUBY_VERSION == '2.7.2'
  raise '/results must be writable' unless File.writable?(RESULTS)
  raise 'Docker socket must not be mounted' if File.exist?('/var/run/docker.sock')
  # Older Debian security backports do not accept this exception through -c.
  # Use a disposable global config inside tmpfs, trusting only this mount.
  git_home = Dir.mktmpdir('p2-git-home-')
  ENV['HOME'] = git_home
  ENV['XDG_CONFIG_HOME'] = File.join(git_home, '.config')
  _out, error, status = Open3.capture3('git', 'config', '--global', '--add', 'safe.directory', CHECKOUT)
  raise "Cannot configure temporary Git trust: #{error}" unless status.success?
  metadata[:head] = git('rev-parse', 'HEAD')
  raise 'Invalid baseline commit' unless metadata[:head].match?(/\A[0-9a-f]{40,64}\z/)
  metadata[:gitStatus] = git('status', '--porcelain=v1', '--untracked-files=all').lines.map(&:chomp)
  input = manifest(CHECKOUT)
  metadata[:inputFingerprint] = fingerprint(input)
  File.write(File.join(RESULTS, 'inputs.sha256'), input.join("\n") + "\n")
  File.write(metadata_path, JSON.pretty_generate(metadata))
  Dir.mktmpdir('p2-unit-') do |work|
    COPY_PATHS.each { |name| FileUtils.cp_r(File.join(CHECKOUT, name), work) }
    FileUtils.mkdir_p(File.join(work, 'dev'))
    FileUtils.cp(File.join(CHECKOUT, 'dev/check_p1.rb'), File.join(work, 'dev/check_p1.rb'))
    raise 'Source changed while copying' unless manifest(work) == input
    # Dependencies in the image must correspond to the mounted lockfiles.
    %w[Gemfile Gemfile.lock].each do |name|
      unless File.binread(File.join(work, name)) == File.binread(File.join('/opt/p1-source', name))
        raise "#{name} differs from the built image; rebuild before testing"
      end
    end
    metadata[:stage] = 'p1-check'
    File.write(metadata_path, JSON.pretty_generate(metadata))
    env = { 'P1_LOG_DIR' => RESULTS, 'P1_BASELINE_SHA' => metadata[:head],
            'P1_INPUT_FINGERPRINT' => metadata[:inputFingerprint], 'SKIP_BUILD' => '1' }
    success = system(env, RbConfig.ruby, '-S', 'bundle', '_2.2.4_', 'exec', 'ruby', 'dev/check_p1.rb', chdir: work)
    raise 'P1 verification failed; see p1-check.log' unless success
    raise 'Mounted inputs changed during verification' unless manifest(CHECKOUT) == input
    raise 'Working copy changed during verification' unless git('rev-parse', 'HEAD') == metadata[:head] &&
      git('status', '--porcelain=v1', '--untracked-files=all').lines.map(&:chomp) == metadata[:gitStatus]
    evidence = File.read(File.join(RESULTS, 'p1-check.log'))
    raise 'Missing P1 completion evidence' unless evidence.include?('All P1 automated checks passed')
  end
  metadata[:result] = 'passed'
  metadata[:stage] = 'complete'
  puts 'P2-01 baseline passed: 113 examples, 3 seeds, standalone specs, M01-M08 and restoration.'
rescue StandardError => error
  metadata[:result] = 'failed'
  metadata[:failure] = error.message
  warn error.message
ensure
  FileUtils.remove_entry(git_home) if git_home && File.directory?(git_home)
  metadata[:finishedUtc] = Time.now.utc.iso8601
  File.write(metadata_path, JSON.pretty_generate(metadata)) if File.writable?(RESULTS)
end
exit(metadata[:result] == 'passed' ? 0 : 1)
