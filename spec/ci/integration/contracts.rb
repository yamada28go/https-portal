require_relative 'client'

$stdout.sync = true
scenario = ENV.fetch('IT_SCENARIO')
phase = ENV.fetch('IT_PHASE', 'check')
seconds = Integer(ENV.fetch('IT_STARTUP_TIMEOUT_SECONDS', '180'))
raise 'Invalid startup timeout' unless (1..900).cover?(seconds)
hosts = { 'redirect' => 'portal.test', 'proxy' => 'proxy.test', 'auth' => 'auth.test',
          'ca' => 'tls.test', 'persistence' => 'portal.test', 'renewal' => 'portal.test', 'static' => 'static.test' }
host = hosts.fetch(scenario)
cases = []
begin
  client = IntegrationClient::Client.new(host, root: scenario == 'ca' ? '/public/root-ca.crt' : nil).ready!(seconds)
  check = lambda do |condition, message|
    IntegrationClient.assert(condition, message)
  end
  case scenario
  when 'redirect'
    path = '/contract/path?x=1&y=two%20words'
    reply = client.request(path, secure: false)
    check.call(reply.code == '301', 'I-02: HTTP response must be 301')
    check.call(reply['location'] == "https://portal.test#{path}", 'I-02: Location must preserve path and query')
    cases << 'I-02'
  when 'proxy'
    reply = client.request('/forward/path?first=one&second=two%20words')
    check.call(reply.code == '200', 'I-03: proxy response must be 200')
    data = JSON.parse(reply.body)
    check.call(data['service'] == 'https-portal-it-echo', 'I-03: expected echo upstream')
    check.call(data['path'] == '/forward/path' && data['query'] == 'first=one&second=two%20words', 'I-03: path/query changed')
    check.call(data['host'] == 'proxy.test' && data['forwarded_proto'] == 'https', 'I-03: Host/Proto headers changed')
    check.call(data['real_ip'] == client.client_ip, 'I-03: X-Real-IP differs from tester address')
    check.call(data['forwarded_for'].to_s.split(',').map(&:strip) == [client.client_ip], 'I-03: X-Forwarded-For differs from tester address')
    cases << 'I-03'
  when 'auth'
    [[nil, '401'], [%w[fixture-user wrong-password], '401'], [%w[fixture-user fixture-password], '200']].each do |credentials, status|
      reply = client.request('/', credentials: credentials)
      check.call(reply.code == status, 'I-04: unexpected authentication response')
      if status == '401'
        check.call(reply['www-authenticate'].to_s.match?(/Basic\s+realm=/i), 'I-04: Basic challenge is missing')
      else
        check.call(JSON.parse(reply.body)['service'] == 'https-portal-it-echo', 'I-04: authenticated response is not upstream')
      end
    end
    cases << 'I-04'
  when 'ca'
    expected = JSON.parse(File.read('/public/expected.json'))
    peer = client.current_tls
    check.call(client.sha256 == expected.fetch('leaf_sha256'), 'I-05: presented leaf differs from generated fixture')
    check.call(peer[:chain].any? { |cert| Digest::SHA256.hexdigest(cert.to_der) == expected.fetch('intermediate_sha256') }, 'I-05: intermediate is not presented')
    check.call(client.request.code == '200', 'I-05: verified HTTPS response must be 200')
    rejected = false
    begin
      client.tls(store: client.store_for(File.read('/public/wrong-ca.crt')))
    rescue OpenSSL::SSL::SSLError
      rejected = true
    end
    check.call(rejected, 'I-05: unrelated CA must be rejected')
    # Keep SNI and routing valid, then require a different certificate hostname.
    # A server-side SNI rejection alone would not prove hostname checking.
    rejected = false
    begin
      root = client.store_for(File.read('/public/root-ca.crt'))
      client.tls(store: root, check_host: 'wrong.test', sni: 'tls.test')
    rescue OpenSSL::SSL::SSLError => error
      rejected = error.message.match?(/hostname|does not match|mismatch/i)
    end
    check.call(rejected, 'I-05: certificate hostname mismatch must be rejected')
    cases << 'I-05'
  when 'persistence', 'renewal'
    state_path = '/public/before.json'
    reply = client.request
    check.call(reply.code == '200' && reply.body.include?('Welcome to HTTPS-PORTAL!'), 'I-06/I-07: welcome response changed')
    if phase == 'before'
      File.write(state_path, JSON.generate(certificate_sha256: client.sha256))
      cases << "#{scenario}-baseline"
    else
      before = JSON.parse(File.read(state_path))
      check.call(client.sha256 == before.fetch('certificate_sha256'), 'I-06/I-07: certificate changed unexpectedly')
      cases << (scenario == 'persistence' ? 'I-06' : 'I-07')
    end
  when 'static'
    { '/' => "HTTPS-PORTAL integration index\n", '/nested/page.txt?x=1' => "HTTPS-PORTAL integration nested page\n" }.each do |path, body|
      reply = client.request(path)
      check.call(reply.code == '200' && reply.body == body, 'I-08: static path or content changed')
    end
    cases << 'I-08'
  end
  puts JSON.generate(result: 'passed', scenario: scenario, phase: phase, cases: cases,
                     certificate_sha256: client.sha256)
rescue StandardError => error
  puts JSON.generate(result: 'failed', scenario: scenario, phase: phase, cases: cases,
                     error: "#{error.class}: #{error.message}")
  warn "Contract failed: #{scenario}/#{phase}: #{error.class}: #{error.message}"
  exit 1
end
