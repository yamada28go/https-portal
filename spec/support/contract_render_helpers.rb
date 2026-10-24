module ContractRenderHelpers
  TEMPLATE_DIR = File.expand_path('../../fs_overlay/var/lib/nginx-conf', __dir__).freeze
  FIXTURE_DIR = File.expand_path('../fixtures/contracts', __dir__).freeze
  ENV_KEYS = %w[
    STAGE PRODUCTION FORCE_RENEW RENEW_MARGIN_DAYS LISTEN_IPV6 HSTS_MAX_AGE
    REDIRECT_CODE WEBSOCKET DYNAMIC_UPSTREAM INDEX_FILES ACME_CHALLENGE_BLOCK
    WORKER_PROCESSES WORKER_CONNECTIONS ACCESS_LOG_INCLUDE_HOST ACCESS_LOG
    ACCESS_LOG_BUFFER ERROR_LOG ERROR_LOG_LEVEL KEEPALIVE_TIMEOUT GZIP
    SERVER_TOKENS SERVER_NAMES_HASH_MAX_SIZE SERVER_NAMES_HASH_BUCKET_SIZE
    CLIENT_MAX_BODY_SIZE PROXY_BUFFERS PROXY_BUFFER_SIZE RESOLVER
    PROXY_CONNECT_TIMEOUT PROXY_SEND_TIMEOUT PROXY_READ_TIMEOUT
    ACCESS_RESTRICTION DEFAULT_SERVER_BLOCK
  ].freeze

  def with_contract_env(values)
    saved = values.keys.to_h { |key| [key, ENV[key]] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def render_contract(template, descriptor = 'example.test')
    domain = Domain.new(descriptor)
    ERBBinding.new(File.join(TEMPLATE_DIR, template), {
      domain: domain,
      acme_challenge_location: Nginx.send(:acme_challenge_location_snippet),
      dhparam_path: NAConfig.dhparam_path
    }).compile
  end

  # Ignore only blank lines, comments and indentation; preserve directive values.
  def contract_lines(config)
    config.lines.map(&:strip).reject { |line| line.empty? || line.start_with?('#') }
  end

  def contract_fixture(name)
    contract_lines(File.read(File.join(FIXTURE_DIR, name)))
  end
end

RSpec.configure do |config|
  config.include ContractRenderHelpers, p1: true

  config.around(:each, p1: true) do |example|
    saved = ENV.to_hash
    (ContractRenderHelpers::ENV_KEYS + ENV.keys.grep(/\ACUSTOM_NGINX_/)).each { |key| ENV.delete(key) }
    ENV['STAGE'] = 'local'
    ENV['FORCE_RENEW'] = 'false'
    ENV['RENEW_MARGIN_DAYS'] = '30'
    example.run
  ensure
    ENV.replace(saved)
  end

  config.before(:each, p1: true) do
    # Domain initialization must not create production certificate directories.
    allow(FileUtils).to receive(:mkdir_p)
    # Fail immediately if the unit under test attempts an external command.
    [OpenSSL, Nginx, ACME, Commands, PortalHelpers].each do |receiver|
      allow(receiver).to receive(:system).and_raise('P1 must not execute external commands')
      allow(receiver).to receive(:`).and_raise('P1 must not execute external commands')
    end
    allow(Process).to receive(:spawn).and_raise('P1 must not spawn processes')
    allow(IO).to receive(:popen).and_raise('P1 must not spawn processes')
  end
end
