# Run inside the development test container: bundle exec ruby dev/check_p1.rb
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

root = File.expand_path('..', __dir__)
paths = %w[spec/models/domain_spec.rb spec/contracts]
log_dir = File.join(__dir__, 'test-results')
FileUtils.mkdir_p(log_dir)
log = File.open(File.join(log_dir, 'p1-check.log'), 'w')

begin
  log.puts "P1 verification started: #{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}"
  log.puts RUBY_DESCRIPTION
  run = lambda do |directory, label, arguments, expected_count, expected_failure|
    command = [RbConfig.ruby, '-S', 'bundle', 'exec', 'rspec', *arguments, '--no-color', '--format', 'progress']
    out, err, status = Open3.capture3({
      'SKIP_BUILD' => '1', 'BUNDLE_GEMFILE' => File.join(directory, 'Gemfile')
    }, *command, chdir: directory)
    output = (out + err).gsub(directory, '<checkout>').gsub(root, '<checkout>')
    summary = output.match(/(\d+) examples?, (\d+) failures?(?:, (\d+) pending)?/)
    correct = summary && summary[1].to_i == expected_count && summary[2].to_i == expected_failure && summary[3].to_i.zero?
    correct &&= expected_failure.zero? ? status.success? : !status.success?
    log.puts "\n#{label}\nCommand: SKIP_BUILD=1 bundle exec rspec #{arguments.join(' ')} --no-color --format progress"
    log.puts "Exit: #{status.exitstatus}\n#{output}"
    log.flush
    raise "#{label} failed; see dev/test-results/p1-check.log" unless correct
    puts "#{label}: PASS (#{summary[0]}; exit #{status.exitstatus})"
  end

  ruby_files = ['spec/p1_helper.rb', *Dir[File.join(root, 'spec/{models,contracts,support}/**/*.rb')]]
  ruby_files.each do |file|
    out, err, status = Open3.capture3(RbConfig.ruby, '-c', file, chdir: root)
    raise "Ruby syntax failed: #{file}\n#{out}#{err}" unless status.success?
  end
  puts 'Ruby syntax: PASS'
  [1, 17, 101].each do |seed|
    run.call(root, "All 54 cases, seed #{seed}", [*paths, '--seed', seed.to_s], 54, 0)
  end
  {
    'spec/models/domain_spec.rb' => 26,
    'spec/contracts/nginx_http_spec.rb' => 4,
    'spec/contracts/nginx_tls_spec.rb' => 4,
    'spec/contracts/nginx_access_spec.rb' => 5,
    'spec/contracts/nginx_routing_spec.rb' => 7,
    'spec/contracts/certificate_renewal_spec.rb' => 8
  }.each do |path, count|
    run.call(root, "Standalone #{path}", [path], count, 0)
  end

  mutations = [
    ['M01', 'fs_overlay/var/lib/nginx-conf/default.conf.erb', 'return    301', 'return    302', 'spec/contracts/nginx_http_spec.rb', 'H01:'],
    ['M02', 'fs_overlay/var/lib/nginx-conf/default.ssl.conf.erb', 'proxy_set_header X-Forwarded-Proto $scheme;', '', 'spec/contracts/nginx_routing_spec.rb', 'R02:'],
    ['M03', 'fs_overlay/var/lib/nginx-conf/default.ssl.conf.erb', 'auth_basic_user_file <%= domain.htaccess_path %>;', '', 'spec/contracts/nginx_access_spec.rb', 'A01:'],
    ['M04', 'fs_overlay/opt/certs_manager/lib/open_ssl.rb', 'expires_in_days(domain.signed_cert_path) > NAConfig.renew_margin_days', 'expires_in_days(domain.signed_cert_path) >= NAConfig.renew_margin_days', 'spec/contracts/certificate_renewal_spec.rb', 'C05:'],
    ['M05', 'fs_overlay/var/lib/nginx-conf/default.ssl.conf.erb', "ENV['REDIRECT_CODE'] || 307", "ENV['REDIRECT_CODE'] || 302", 'spec/contracts/nginx_routing_spec.rb', 'R04:']
  ]

  # Mutate an isolated checkout copy, never the actual product files.
  Dir.mktmpdir('https-portal-p1-') do |scratch|
    %w[spec fs_overlay Gemfile Gemfile.lock .rspec].each do |name|
      FileUtils.cp_r(File.join(root, name), scratch)
    end
    mutations.each do |id, relative_path, from, to, spec, example|
      path = File.join(scratch, relative_path)
      original = File.binread(path)
      raise "#{id}: mutation anchor is not unique" unless original.scan(from).length == 1
      args = [spec, '--example', example]
      run.call(scratch, "#{id} before", args, 1, 0)
      begin
        File.binwrite(path, original.sub(from, to))
        log.puts "#{id} change: #{relative_path}\n- #{from}\n+ #{to}"
        run.call(scratch, "#{id} detected", args, 1, 1)
      ensure
        File.binwrite(path, original)
      end
      raise "#{id}: restoration failed" unless File.binread(path) == original
      run.call(scratch, "#{id} restored", args, 1, 0)
    end
    run.call(scratch, 'All cases after restoration', paths, 54, 0)
  end
  log.puts "\nAll P1 automated checks passed. Human review remains separate."
  puts 'P1 checks passed. Evidence: dev/test-results/p1-check.log'
rescue StandardError => error
  log.puts "\nFAILED: #{error.message.gsub(root, '<checkout>')}"
  warn error.message
  exit 1
ensure
  log.close
end
