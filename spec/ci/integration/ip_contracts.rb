require_relative 'client'
require 'ipaddr'

$stdout.sync = true
scenario = ENV.fetch('IT_SCENARIO')
role = ENV.fetch('IT_ROLE')
raise 'Unexpected IP scenario' unless %w[ip ip-auth].include?(scenario)
raise 'Unexpected IP role' unless %w[allowed denied].include?(role)
allowed_ip = ENV.fetch('IT_ALLOWED_IP')
raise 'Expected IPv4 allow address' unless IPAddr.new(allowed_ip).ipv4?
seconds = Integer(ENV.fetch('IT_STARTUP_TIMEOUT_SECONDS', '180'))
raise 'Invalid startup timeout' unless (1..900).cover?(seconds)
host = scenario == 'ip' ? 'ip.test' : 'ip-auth.test'
credentials = scenario == 'ip-auth' ? %w[fixture-user fixture-password] : nil
cases = []
checks = []
client = nil
begin
  if role == 'allowed'
    client = IntegrationClient::Client.new(host).ready!(seconds)
  else
    # The allowed client already proved readiness and exported the public leaf.
    # No readiness retry here: unexpected 200/401 must fail the actual assertion.
    client = IntegrationClient::Client.new(host, root: '/public/ip-leaf.crt')
    client.establish_trust
  end
  IntegrationClient.assert((client.client_ip == allowed_ip) == (role == 'allowed'), 'Unexpected source IP for role')
  verify_reply = lambda do |reply, status, label|
    IntegrationClient.assert(reply.code == status, "#{label}: expected #{status}, got #{reply.code}")
    if status == '200'
      IntegrationClient.assert(JSON.parse(reply.body)['service'] == 'https-portal-it-echo', "#{label}: upstream missing")
    elsif status == '401'
      IntegrationClient.assert(reply['www-authenticate'].to_s.match?(/Basic\s+realm=/i), "#{label}: Basic challenge missing")
    end
    checks << { check: label, status: reply.code }
  end
  if role == 'allowed'
    verify_reply.call(client.request(credentials: credentials), '200', 'allowed')
    if scenario == 'ip-auth'
      verify_reply.call(client.request, '401', 'allowed-no-auth')
      verify_reply.call(client.request(credentials: %w[fixture-user wrong-password]), '401', 'allowed-wrong-auth')
      cases << 'S-T06-allowed'
    else
      cases << 'S-T04-allowed'
    end
    File.write('/public/ip-leaf.crt', client.cert.to_pem)
  else
    verify_reply.call(client.request(credentials: credentials), '403', 'denied')
    cases << (scenario == 'ip-auth' ? 'S-T06-denied' : 'S-T04-denied')
    [ { 'X-Forwarded-For' => allowed_ip }, { 'X-Real-IP' => allowed_ip },
      { 'X-Forwarded-For' => allowed_ip, 'X-Real-IP' => allowed_ip } ].each_with_index do |headers, index|
      verify_reply.call(client.request(credentials: credentials, headers: headers), '403', "spoof-#{index + 1}")
    end
    cases << 'S-T05'
  end
  puts JSON.generate(result: 'passed', scenario: scenario, role: role, cases: cases, checks: checks,
                     source_ip: client.client_ip, allowed_ip: allowed_ip, certificate_sha256: client.sha256)
rescue StandardError => error
  puts JSON.generate(result: 'failed', scenario: scenario, role: role, cases: cases, checks: checks,
                     error: "#{error.class}: #{error.message}")
  warn "IP contract failed: #{scenario}/#{role}: #{error.class}: #{error.message}"
  exit 1
end