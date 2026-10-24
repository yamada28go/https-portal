require_relative '../p1_helper'

RSpec.describe 'C-02: domain input boundaries and malformed descriptors', :p1 do
  # Characterization only: accepted unsafe values below are documented gaps,
  # not approved input validation or security requirements.
  before do
    allow(STDERR).to receive(:puts)
  end

  {
    'C-02-01: unset DOMAINS produces no domains' => nil,
    'C-02-02: empty DOMAINS produces no domains' => '',
    'C-02-03: whitespace-only DOMAINS produces no domains' => " \t\r\n ",
    'C-02-04: delimiter-only DOMAINS produces no domains' => ' , , '
  }.each do |description, value|
    it description do
      with_contract_env('DOMAINS' => value) do
        expect(FileUtils).not_to receive(:mkdir_p)
        expect(NAConfig.env_domains).to eq([])
      end
    end
  end

  [
    ['C-02-05: a directly supplied empty descriptor fails', ''],
    ['C-02-06: a directly supplied whitespace descriptor fails', " \t\r\n "],
    ['C-02-07: a nonnumeric port fails', 'example.test:https'],
    ['C-02-08: a negative port fails', 'example.test:-1'],
    ['C-02-09: a port separator without a value fails', 'example.test:'],
    ['C-02-10: a fractional port fails', 'example.test:443.5'],
    ['C-02-11: a proxy arrow without an upstream fails', 'example.test ->'],
    ['C-02-12: a redirect arrow without a target fails', 'example.test =>'],
    ['C-02-13: a malformed proxy arrow fails', 'example.test --> http://upstream.test'],
    ['C-02-14: an unterminated access list fails', '[192.0.2.0/24example.test'],
    ['C-02-15: credentials without a domain fail', 'fixture-user:fixture-secret@'],
    ['C-02-16: a tab inside the hostname fails', "exam\tple.test"],
    ['C-02-17: a NUL inside the hostname fails', "exam\0ple.test"],
    ['C-02-18: an escape character inside the hostname fails', "exam\eple.test"]
  ].each do |description, descriptor|
    it description, :aggregate_failures do
      expect(FileUtils).not_to receive(:mkdir_p)
      expect(STDERR).to receive(:puts).with("Error: Invalid descriptor #{descriptor}")
      # The parser returns nil; initialize then indexes nil while resolving dir.
      # Keep this accidental exception visible until explicit validation is added.
      expect { Domain.new(descriptor) }.to raise_error(NoMethodError) { |error|
        expect(error.name).to eq(:[])
        expect(error.receiver).to be_nil
      }
    end
  end

  {
    'C-02-19: characterizes accepting port zero' => '0',
    'C-02-20: preserves the upper valid port boundary' => '65535',
    'C-02-21: characterizes accepting a port above 65535' => '65536',
    'C-02-22: preserves leading zeros in a port' => '00443'
  }.each do |description, port|
    it description, :aggregate_failures do
      domain = Domain.new("example.test:#{port}")
      expect(domain.name).to eq('example.test')
      expect(domain.port).to eq(port)
      expect(domain.stage).to eq('local')
      expect(STDERR).not_to have_received(:puts)
    end
  end

  {
    'C-02-23: characterizes ignoring an invalid suffix line' => "example.test\ninvalid!",
    'C-02-24: characterizes matching after an invalid prefix line' => "invalid!\nexample.test"
  }.each do |description, descriptor|
    it description, :aggregate_failures do
      domain = Domain.new(descriptor)
      expect(domain.descriptor).to eq(descriptor)
      expect(domain.name).to eq('example.test')
      expect(domain.port).to eq('443')
      expect(STDERR).not_to have_received(:puts)
    end
  end

  it 'C-02-25: rejects redirect parameters when the target is evaluated' do
    domain = Domain.new('example.test => target.test[backup]')
    expect { domain.redirect_target_url }.to raise_error(RuntimeError, 'Parameters not supported on redirect-target')
  end

  it 'C-02-26: characterizes the initialization failure for an unknown stage', :aggregate_failures do
    expect(FileUtils).not_to receive(:mkdir_p)
    expect(STDERR).to receive(:puts).with('Error: Invalid stage unknown')
    expect { Domain.new('example.test #unknown') }.to raise_error(TypeError)
  end

  it 'C-02-27: ignores empty list entries without losing valid descriptors', :aggregate_failures do
    with_contract_env('DOMAINS' => ' , example.test ,, other.test:4443, ') do
      domains = NAConfig.env_domains
      expect(domains.map(&:name)).to eq(['example.test', 'other.test'])
      expect(domains.map(&:port)).to eq(['443', '4443'])
    end
  end

  it 'C-02-28: characterizes accepting an invalid numeric IP and CIDR', :aggregate_failures do
    domain = Domain.new('[999.999.999.999/99]example.test')
    expect(domain.name).to eq('example.test')
    expect(domain.access_restriction).to eq(['999.999.999.999/99'])
    expect(STDERR).not_to have_received(:puts)
  end

  it 'C-02-29: characterizes treating an unsupported protocol as an HTTP address', :aggregate_failures do
    domain = Domain.new('example.test -> ftp://upstream.test')
    expect(domain.upstream_proto).to eq('http://')
    expect(domain.upstreams).to eq([{ address: 'ftp://upstream.test', parameters: nil }])
    expect(domain.upstream).to eq('http://ftp://upstream.test')
    expect(STDERR).not_to have_received(:puts)
  end
end
