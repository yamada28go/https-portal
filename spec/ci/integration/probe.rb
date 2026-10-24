require 'digest'
require 'json'
require 'net/http'
require 'openssl'
require 'socket'
require 'timeout'

class NotReady < StandardError; end

$stdout.sync = true
host = ENV.fetch('IT_TARGET_HOST', 'portal.test')
raise 'Only the fixed internal fixture is allowed' unless host == 'portal.test'
seconds = Integer(ENV.fetch('IT_STARTUP_TIMEOUT_SECONDS', '180'))
raise 'Startup timeout must be 1..900' unless (1..900).cover?(seconds)
expected = ENV.fetch('IT_EXPECTED_BODY', 'Welcome to HTTPS-PORTAL!')
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
last_error = nil
attempt = 0

loop do
  remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
  break if remaining <= 0
  attempt += 1
  begin
    # Discovery only: bootstrap the local self-signed leaf, then use a verified
    # HTTPS connection pinned to it. Independent CA trust is a P2-04 test.
    cert = Timeout.timeout([remaining, 10].min) do
      tcp = nil
      ssl = nil
      begin
        tcp = TCPSocket.new(host, 443)
        context = OpenSSL::SSL::SSLContext.new
        context.verify_mode = OpenSSL::SSL::VERIFY_NONE
        ssl = OpenSSL::SSL::SSLSocket.new(tcp, context)
        ssl.hostname = host
        ssl.connect
        ssl.peer_cert
      ensure
        ssl.close if ssl
        tcp.close if tcp && !tcp.closed?
      end
    end
    raise NotReady, 'Certificate hostname is not ready' unless OpenSSL::SSL.verify_certificate_identity(cert, host)
    raise NotReady, 'Local leaf is not self-signed' unless cert.issuer == cert.subject && cert.verify(cert.public_key)
    raise NotReady, 'Certificate is outside validity' unless cert.not_before <= Time.now && Time.now < cert.not_after
    store = OpenSSL::X509::Store.new
    store.add_cert(cert)
    remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    raise Timeout::Error, 'Startup deadline reached' if remaining <= 0
    Timeout.timeout([remaining, 10].min) do
      http = Net::HTTP.new(host, 443, nil) # Never use host proxy environment.
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      # Ruby 2.7 Net::HTTP performs post_connection_check(host) with VERIFY_PEER.
      http.cert_store = store
      http.open_timeout = 5
      http.read_timeout = 5
      response = http.get('/')
      raise NotReady, "HTTPS not ready: #{response.code}" unless response.code == '200'
      raise NotReady, 'Expected welcome content is not ready' unless response.body.include?(expected)
      echo = Net::HTTP.new('echo', 8080, nil)
      echo.open_timeout = 5
      echo.read_timeout = 5
      reply = echo.get('/ready')
      raise NotReady, 'Echo fixture not ready' unless reply.code == '200' && JSON.parse(reply.body)['service'] == 'https-portal-it-echo'
    end
    puts JSON.generate(result: 'passed', scenario: 'local', attempts: attempt,
                       host: host, status: 200, certificate_sha256: Digest::SHA256.hexdigest(cert.to_der))
    exit 0
  rescue NotReady, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Timeout::Error, Net::HTTPBadResponse => error
    last_error = "#{error.class}: #{error.message}"
    remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    sleep [remaining, 1].min if remaining > 0
  rescue StandardError => error
    # A programming/API error will not recover by waiting for portal startup.
    puts JSON.generate(result: 'failed', scenario: 'local', phase: 'probe_error',
                       attempts: attempt, error: "#{error.class}: #{error.message}")
    warn "Probe error (not retried): #{error.class}: #{error.message}"
    exit 2
  end
end
puts JSON.generate(result: 'failed', scenario: 'local', attempts: attempt,
                   timeout_seconds: seconds, last_error: last_error)
warn "Readiness timed out after #{seconds}s: #{last_error}"
exit 1
