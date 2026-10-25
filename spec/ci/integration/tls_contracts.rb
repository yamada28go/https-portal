require_relative 'client'

# Prove this client can actually speak each obsolete protocol before requiring
# the portal to reject it. The control server is loopback-only and short-lived.
def legacy_control(version, expected_version)
  key = OpenSSL::PKey::RSA.new(2048)
  cert = OpenSSL::X509::Certificate.new
  cert.version = 2
  cert.serial = 1
  cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=capability.test')
  cert.public_key = key.public_key
  cert.not_before = Time.now - 60
  cert.not_after = Time.now + 3600
  factory = OpenSSL::X509::ExtensionFactory.new
  factory.subject_certificate = factory.issuer_certificate = cert
  cert.add_extension(factory.create_extension('subjectAltName', 'DNS:capability.test'))
  cert.sign(key, OpenSSL::Digest::SHA256.new)
  listener = worker = tcp = ssl = nil
  begin
    Timeout.timeout(10) do
      server_context = OpenSSL::SSL::SSLContext.new
      server_context.min_version = server_context.max_version = version
      server_context.security_level = 0
      server_context.ciphers = 'AES128-SHA:@SECLEVEL=0'
      server_context.cert = cert
      server_context.key = key
      listener = TCPServer.new('127.0.0.1', 0)
      server = OpenSSL::SSL::SSLServer.new(listener, server_context)
      worker = Thread.new do
        peer = nil
        begin
          peer = server.accept
          peer.ssl_version
        ensure
          peer.close if peer
        end
      end
      worker.report_on_exception = false
      store = OpenSSL::X509::Store.new
      store.add_cert(cert)
      context = OpenSSL::SSL::SSLContext.new
      context.min_version = context.max_version = version
      context.security_level = 0
      context.ciphers = 'AES128-SHA:@SECLEVEL=0'
      context.verify_mode = OpenSSL::SSL::VERIFY_PEER
      context.cert_store = store
      tcp = TCPSocket.new('127.0.0.1', listener.addr[1])
      ssl = OpenSSL::SSL::SSLSocket.new(tcp, context)
      ssl.hostname = 'capability.test'
      ssl.connect
      ssl.post_connection_check('capability.test')
      IntegrationClient.assert(ssl.ssl_version == expected_version, 'Legacy client control negotiated wrong protocol')
      IntegrationClient.assert(worker.value == expected_version, 'Legacy server control negotiated wrong protocol')
    end
  ensure
    ssl.close if ssl
    tcp.close if tcp && !tcp.closed?
    listener.close if listener && !listener.closed?
    if worker
      worker.kill if worker.alive?
      worker.join
    end
  end
end

def wait_for_variant(client, expected, scenario, seconds)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
  stable = 0
  last = nil
  loop do
    remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    break if remaining <= 0
    begin
      Timeout.timeout([remaining, 10].min) do
        # Observe the exact presented fixture; this does not count as validation.
        peer = client.tls
        fingerprint = Digest::SHA256.hexdigest(peer[:cert].to_der)
        intermediate = peer[:chain].any? { |cert| Digest::SHA256.hexdigest(cert.to_der) == expected.fetch('intermediate_sha256') }
        wanted = scenario == 'tls-chain' ? expected.fetch('leaf_sha256') : expected.fetch('expired_sha256')
        matches = fingerprint == wanted && (scenario == 'tls-chain' ? !intermediate : intermediate)
        stable = matches ? stable + 1 : 0
        return peer if stable >= 3
        last = "Waiting for #{scenario} fixture after reload"
      end
    rescue *IntegrationClient::TRANSIENT => error
      stable = 0
      last = "#{error.class}: #{error.message}"
    end
    remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sleep [remaining, 1].min if remaining > 0
  end
  raise IntegrationClient::NotReady, "Certificate reload timed out: #{last}"
end

$stdout.sync = true
scenario = ENV.fetch('IT_SCENARIO')
phase = ENV.fetch('IT_PHASE', 'check')
raise 'Unexpected TLS scenario' unless %w[tls-policy tls-chain tls-expired].include?(scenario)
raise 'Unexpected TLS phase' unless %w[check baseline mutated restored].include?(phase)
seconds = Integer(ENV.fetch('IT_STARTUP_TIMEOUT_SECONDS', '180'))
raise 'Invalid startup timeout' unless (1..900).cover?(seconds)
expected = JSON.parse(File.read('/public/expected.json'))
checks = []
cases = []
client = IntegrationClient::Client.new('tls.test', root: '/public/root-ca.crt')
begin
  if phase == 'mutated'
    raise 'Policy scenario has no certificate mutation' if scenario == 'tls-policy'
    peer = wait_for_variant(client, expected, scenario, seconds)
    cert = peer[:cert]
    IntegrationClient.assert(OpenSSL::SSL.verify_certificate_identity(cert, 'tls.test'), 'Mutated certificate SAN mismatch')
    if scenario == 'tls-expired'
      IntegrationClient.assert(cert.not_before < cert.not_after && cert.not_after < Time.now, 'Expected a correctly ordered, expired validity interval')
    end
    # Fresh trust store has only root. Never add the intermediate or observed leaf.
    expected_codes = scenario == 'tls-chain' ? [20, 21] : [10]
    rejected = false
    begin
      client.tls(store: client.store_for(File.read('/public/root-ca.crt')))
    rescue IntegrationClient::TLSFailure => error
      rejected = expected_codes.include?(error.verification_code)
      checks << { check: 'certificate-rejection', verification_code: error.verification_code, error: error.message }
    end
    IntegrationClient.assert(rejected, 'Expected certificate verification failure with the specific chain/expiry reason')
    checks << { check: 'presented-fixture', certificate_sha256: Digest::SHA256.hexdigest(cert.to_der) }
    cases << (scenario == 'tls-chain' ? 'S-T02-negative' : 'S-T03-negative')
  else
    client.ready!(seconds)
    IntegrationClient.assert(client.sha256 == expected.fetch('leaf_sha256'), 'Valid fixture leaf changed')
    IntegrationClient.assert(client.request.code == '200', 'Verified HTTPS must return 200')
    checks << { check: 'verified-https', status: '200', certificate_sha256: client.sha256 }
    if scenario == 'tls-policy'
      raise 'Policy uses only check phase' unless phase == 'check'
      store = client.store_for(File.read('/public/root-ca.crt'))
      [[OpenSSL::SSL::TLS1_2_VERSION, 'TLSv1.2'], [OpenSSL::SSL::TLS1_3_VERSION, 'TLSv1.3']].each do |version, label|
        peer = client.tls(store: store, version: version)
        IntegrationClient.assert(peer[:version] == label, "Expected #{label}")
        checks << { check: label, result: 'accepted' }
      end
      [[OpenSSL::SSL::TLS1_VERSION, 'TLSv1'], [OpenSSL::SSL::TLS1_1_VERSION, 'TLSv1.1']].each do |version, label|
        legacy_control(version, label)
        checks << { check: "#{label}-capability", result: 'accepted-on-loopback-control' }
        rejected = false
        begin
          client.tls(store: store, version: version, legacy: true)
        rescue OpenSSL::SSL::SSLError => error
          rejected = error.message.match?(/alert protocol version/i)
          checks << { check: label, error: error.message }
        end
        IntegrationClient.assert(rejected, "Expected server protocol-version alert for #{label}")
      end
      cases << 'S-T07'
      ['unknown.test', nil].each do |sni|
        rejected = false
        begin
          client.tls(store: store, sni: sni)
        rescue OpenSSL::SSL::SSLError => error
          rejected = error.message.match?(/unrecognized[ _]name/i)
          checks << { check: sni || 'no-sni', error: error.message }
        end
        IntegrationClient.assert(rejected, 'Expected unrecognized_name rejection from default SSL server')
      end
      cases << 'S-T08'
    else
      raise 'Certificate test needs baseline or restored phase' unless %w[baseline restored].include?(phase)
      cases << "#{scenario == 'tls-chain' ? 'S-T02' : 'S-T03'}-#{phase}"
    end
  end
  puts JSON.generate(result: 'passed', scenario: scenario, phase: phase, cases: cases, checks: checks,
                     openssl: OpenSSL::OPENSSL_VERSION)
rescue StandardError => error
  puts JSON.generate(result: 'failed', scenario: scenario, phase: phase, cases: cases, checks: checks,
                     openssl: OpenSSL::OPENSSL_VERSION, error: "#{error.class}: #{error.message}")
  warn "TLS contract failed: #{scenario}/#{phase}: #{error.class}: #{error.message}"
  exit 1
end