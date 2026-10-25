# Stdlib-only checks for the integration harness, run while building both CPUs.
require_relative 'client'
require 'stringio'

def check(name)
  yield
  puts "Integration client: #{name}: passed"
end

def assert(value)
  raise 'Client harness assertion failed' unless value
end

class ReadyFixture < IntegrationClient::Client
  attr_reader :attempts
  def initialize(failures: [], fingerprints: nil, advance_clock: nil)
    super('proxy.test')
    @failures = failures
    @fingerprints = fingerprints
    @advance_clock = advance_clock
    @attempts = 0
  end
  def establish_trust
    @attempts += 1
    # This fails if ready! starts its own asynchronous timer around operations.
    assert(Thread.list.length == 1)
    @advance_clock.call(6) if @advance_clock
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
  # Advance the clock used by BOTH ready!'s loop and the operation budget.
  # Mutating only @readiness_deadline leaves the loop's local deadline intact.
  original_clock = Process.method(:clock_gettime)
  now = 100.0
  Process.define_singleton_method(:clock_gettime) do |clock, *args|
    clock == Process::CLOCK_MONOTONIC ? now : original_clock.call(clock, *args)
  end
  begin
    client = ReadyFixture.new(advance_clock: ->(seconds) { now += seconds })
    begin
      client.ready!(5)
      raise 'Expired readiness was accepted'
    rescue IntegrationClient::NotReady => error
      assert(error.message.include?('Startup deadline reached'))
      assert(client.attempts == 1 && client.operation_timeout(10) == 10)
    end
  ensure
    Process.define_singleton_method(:clock_gettime, original_clock)
  end
end
check('operation timeout uses remaining startup budget') do
  client = IntegrationClient::Client.new('proxy.test')
  client.instance_variable_set(:@readiness_deadline, Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.5)
  assert(client.operation_timeout(10) > 0 && client.operation_timeout(10) <= 0.5)
end

class HTTPFixture
  attr_accessor :use_ssl, :verify_mode, :cert_store, :open_timeout, :read_timeout, :write_timeout, :max_retries
  attr_reader :sent, :calls
  def initialize(outcomes = [])
    @outcomes = outcomes
    @calls = 0
  end
  def request(req)
    assert(Thread.list.length == 1)
    @sent = req
    @calls += 1
    outcome = @outcomes.shift || :fixture_response
    raise outcome if outcome.is_a?(Exception)
    outcome
  end
end
original_new = Net::HTTP.method(:new)
http = HTTPFixture.new
Net::HTTP.define_singleton_method(:new) do |host, port, proxy|
  raise 'Unexpected request destination' unless host == 'proxy.test' && port == 443 && proxy.nil?
  http
end
begin
  check('HTTP uses native bounds, verified TLS and no Net::HTTP internal retry') do
    client = IntegrationClient::Client.new('proxy.test')
    assert(client.request('/fixture?x=1', headers: { 'X-Fixture' => 'yes' }) == :fixture_response)
    assert(http.use_ssl && http.verify_mode == OpenSSL::SSL::VERIFY_PEER)
    assert([http.open_timeout, http.read_timeout, http.write_timeout] == [5, 5, 5])
    assert(http.max_retries == 0 && http.sent.path == '/fixture?x=1' && http.sent['X-Fixture'] == 'yes')
  end
  previous_stderr = $stderr
  warnings = StringIO.new
  $stderr = warnings
  begin
    check('connection timeout retries with visible evidence') do
      http = HTTPFixture.new([Net::OpenTimeout.new('fixture connect timeout')])
      client = IntegrationClient::Client.new('proxy.test')
      assert(client.request == :fixture_response && http.calls == 2)
      assert(warnings.string.include?('host=proxy.test attempt=1/3'))
    end
    check('persistent connection timeout fails after three attempts') do
      http = HTTPFixture.new(Array.new(3) { Net::OpenTimeout.new('fixture connect timeout') })
      client = IntegrationClient::Client.new('proxy.test')
      begin
        client.request
        raise 'Persistent connection timeout was swallowed'
      rescue Net::OpenTimeout
        assert(http.calls == 3 && warnings.string.include?('attempt=3/3'))
      end
    end
    check('read timeout is not retried') do
      http = HTTPFixture.new([Net::ReadTimeout.new('fixture read timeout')])
      begin
        IntegrationClient::Client.new('proxy.test').request
        raise 'Read timeout was swallowed'
      rescue Net::ReadTimeout
        assert(http.calls == 1)
      end
    end
    check('certificate error is not retried') do
      http = HTTPFixture.new([OpenSSL::SSL::SSLError.new('fixture certificate rejected')])
      begin
        IntegrationClient::Client.new('proxy.test').request
        raise 'Certificate error was swallowed'
      rescue OpenSSL::SSL::SSLError
        assert(http.calls == 1)
      end
    end
    check('unexpected HTTP status fails the contract without retry') do
      http = HTTPFixture.new([Struct.new(:code).new('200')])
      begin
        reply = IntegrationClient::Client.new('proxy.test').request
        IntegrationClient.assert(reply.code == '403', 'fixture expected 403')
        raise 'Contract failure was swallowed'
      rescue IntegrationClient::ContractFailure
        assert(http.calls == 1)
      end
    end
  ensure
    $stderr = previous_stderr
  end
ensure
  Net::HTTP.define_singleton_method(:new, original_new)
end
