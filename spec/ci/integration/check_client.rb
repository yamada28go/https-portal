# Stdlib-only checks for the integration harness, run while building both CPUs.
require_relative 'client'

def check(name)
  yield
  puts "Integration client: #{name}: passed"
end

def assert(value)
  raise 'Client harness assertion failed' unless value
end

class ReadyFixture < IntegrationClient::Client
  attr_reader :attempts
  def initialize(failures: [], fingerprints: nil, expire: false)
    super('proxy.test')
    @failures = failures
    @fingerprints = fingerprints
    @expire = expire
    @attempts = 0
  end
  def establish_trust
    @attempts += 1
    # This fails if ready! starts its own asynchronous timer around operations.
    assert(Thread.list.length == 1)
    @readiness_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1 if @expire
    failure = @failures.shift
    raise failure if failure
  end
  def request(*)
    operation_timeout(5)
    Struct.new(:code).new('200')
  end
  def sha256
    @fingerprints ? (@fingerprints.shift || 'new') : 'same'
  end
  def sleep(*)
    # Deterministic readiness checks do not need a real pause.
  end
end

check('three stable observations without nested timer') do
  client = ReadyFixture.new
  assert(client.ready!(5).equal?(client) && client.attempts == 3)
  assert(client.operation_timeout(10) == 10)
end
check('transient timeout retries') do
  client = ReadyFixture.new(failures: [Timeout::Error.new('fixture timeout')])
  client.ready!(5)
  assert(client.attempts == 4)
end
check('certificate change resets stability') do
  client = ReadyFixture.new(fingerprints: %w[old old new new new])
  client.ready!(5)
  assert(client.attempts == 5)
end
check('contract failure is not retried') do
  client = ReadyFixture.new(failures: [IntegrationClient::ContractFailure.new('fixture contract')])
  begin
    client.ready!(5)
    raise 'Contract failure was swallowed'
  rescue IntegrationClient::ContractFailure
    assert(client.attempts == 1 && client.operation_timeout(10) == 10)
  end
end
check('expired startup deadline fails and clears budget') do
  client = ReadyFixture.new(expire: true)
  begin
    client.ready!(5)
    raise 'Expired readiness was accepted'
  rescue IntegrationClient::NotReady => error
    assert(error.message.include?('Startup deadline reached'))
    assert(client.attempts == 1 && client.operation_timeout(10) == 10)
  end
end
check('operation timeout uses remaining startup budget') do
  client = IntegrationClient::Client.new('proxy.test')
  client.instance_variable_set(:@readiness_deadline, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.5)
  assert(client.operation_timeout(10) > 0 && client.operation_timeout(10) <= 0.5)
end

class HTTPFixture
  attr_accessor :use_ssl, :verify_mode, :cert_store, :open_timeout, :read_timeout, :write_timeout, :max_retries
  attr_reader :sent
  def request(req)
    assert(Thread.list.length == 1)
    @sent = req
    :fixture_response
  end
end
original_new = Net::HTTP.method(:new)
http = HTTPFixture.new
Net::HTTP.define_singleton_method(:new) do |host, port, proxy|
  raise 'Unexpected request destination' unless host == 'proxy.test' && port == 443 && proxy.nil?
  http
end
begin
  check('HTTP uses native bounds, verified TLS and no automatic retry') do
    client = IntegrationClient::Client.new('proxy.test')
    assert(client.request('/fixture?x=1', headers: { 'X-Fixture' => 'yes' }) == :fixture_response)
    assert(http.use_ssl && http.verify_mode == OpenSSL::SSL::VERIFY_PEER)
    assert([http.open_timeout, http.read_timeout, http.write_timeout] == [5, 5, 5])
    assert(http.max_retries == 0 && http.sent.path == '/fixture?x=1' && http.sent['X-Fixture'] == 'yes')
  end
ensure
  Net::HTTP.define_singleton_method(:new, original_new)
end
