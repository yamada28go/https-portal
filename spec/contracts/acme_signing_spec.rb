require_relative '../p1_helper'
require 'tmpdir'

RSpec.describe 'C-07: current ACME signing behavior', :p1 do
  around do |example|
    Dir.mktmpdir('https-portal-acme-') do |directory|
      @cert_directory = directory
      example.run
    end
  end

  let(:domain) { Domain.new('example.test #staging') }

  before do
    allow(domain).to receive(:dir).and_return(@cert_directory)
    allow(NAConfig).to receive(:portal_base_dir).and_return(@cert_directory)
    File.binwrite(domain.signed_cert_path, 'old-cert')
    File.binwrite(domain.key_path, 'old-key')
    File.binwrite(domain.ongoing_cert_path, 'new-cert')
    File.binwrite(domain.ongoing_key_path, 'new-key')
    allow(ACME).to receive(:puts)
    allow(Timeout).to receive(:timeout).with(120).and_yield
    allow(ACME).to receive(:system).with(a_string_matching(/\A\s*acme_tiny\b/)).and_return(true)
  end

  def expect_certificates(cert, key)
    expect(File.binread(domain.signed_cert_path)).to eq(cert)
    expect(File.binread(domain.key_path)).to eq(key)
  end

  it 'C-07-01: installs both staged files after a successful signing command', :aggregate_failures do
    expect(ACME.sign(domain)).to be_truthy
    expect_certificates('new-cert', 'new-key')
    expect(File.exist?(domain.ongoing_cert_path)).to eq(false)
    expect(File.exist?(domain.ongoing_key_path)).to eq(false)
    expect(Timeout).to have_received(:timeout).with(120)
    expect(ACME).to have_received(:system).with(include(
      'acme_tiny', "--account-key #{@cert_directory}/account.key",
      "--csr #{domain.csr_path}", '--acme-dir /var/www/default/challenges/',
      '--disable-check', "--directory-url #{domain.ca}", "> #{domain.ongoing_cert_path}"
    ))
  end

  it 'C-07-02: returns false and preserves installed files when the command fails', :aggregate_failures do
    allow(ACME).to receive(:system).with(a_string_matching(/\A\s*acme_tiny\b/)).and_return(false)
    expect(FileUtils).not_to receive(:mv)
    expect(ACME.sign(domain)).to eq(false)
    expect_certificates('old-cert', 'old-key')
    expect(File.binread(domain.ongoing_cert_path)).to eq('new-cert')
    expect(File.binread(domain.ongoing_key_path)).to eq('new-key')
  end

  it 'C-07-03: returns false when the signing command cannot be started', :aggregate_failures do
    allow(ACME).to receive(:system).with(a_string_matching(/\A\s*acme_tiny\b/)).and_return(nil)
    expect(FileUtils).not_to receive(:mv)
    expect(ACME.sign(domain)).to eq(false)
    expect_certificates('old-cert', 'old-key')
  end

  it 'C-07-04: returns false on timeout without replacing installed files', :aggregate_failures do
    allow(ACME).to receive(:system).with(a_string_matching(/\A\s*acme_tiny\b/)).and_raise(Timeout::Error)
    expect(FileUtils).not_to receive(:mv)
    expect(ACME.sign(domain)).to eq(false)
    expect_certificates('old-cert', 'old-key')
    expect(Timeout).to have_received(:timeout).with(120)
  end

  it 'C-07-05: ignores a missing staged certificate and still installs the new key', :aggregate_failures do
    File.delete(domain.ongoing_cert_path)
    expect { ACME.sign(domain) }.not_to raise_error
    expect_certificates('old-cert', 'new-key')
  end

  it 'C-07-06: ignores a missing staged key and keeps the new certificate and old key', :aggregate_failures do
    File.delete(domain.ongoing_key_path)
    expect { ACME.sign(domain) }.not_to raise_error
    expect_certificates('new-cert', 'old-key')
    expect(File.exist?(domain.ongoing_cert_path)).to eq(false)
  end

  it 'C-07-07: ignores a certificate rename permission error and still replaces the key', :aggregate_failures do
    allow(File).to receive(:rename).and_call_original
    allow(File).to receive(:rename).with(domain.ongoing_cert_path, domain.signed_cert_path).and_raise(Errno::EACCES)
    expect { ACME.sign(domain) }.not_to raise_error
    expect_certificates('old-cert', 'new-key')
    expect(File.binread(domain.ongoing_cert_path)).to eq('new-cert')
  end

  it 'C-07-08: ignores a key rename permission error without rolling back the certificate', :aggregate_failures do
    allow(File).to receive(:rename).and_call_original
    allow(File).to receive(:rename).with(domain.ongoing_key_path, domain.key_path).and_raise(Errno::EACCES)
    expect { ACME.sign(domain) }.not_to raise_error
    expect_certificates('new-cert', 'old-key')
    expect(File.binread(domain.ongoing_key_path)).to eq('new-key')
  end

  it 'C-07-09: delegates local signing and returns its success value' do
    local = Domain.new('example.test #local')
    expect(OpenSSL).to receive(:self_sign).with(local).and_return(true)
    expect(ACME).not_to receive(:system)
    expect(Timeout).not_to receive(:timeout)
    expect(FileUtils).not_to receive(:mv)
    expect(ACME.sign(local)).to eq(true)
  end

  it 'C-07-10: returns false when local self-signing returns false' do
    local = Domain.new('example.test #local')
    expect(OpenSSL).to receive(:self_sign).with(local).and_return(false)
    expect(ACME).not_to receive(:system)
    expect(ACME.sign(local)).to eq(false)
  end

  it 'C-07-11: converts a timeout during local signing to false' do
    local = Domain.new('example.test #local')
    expect(OpenSSL).to receive(:self_sign).with(local).and_raise(Timeout::Error)
    expect(ACME).not_to receive(:system)
    expect(ACME.sign(local)).to eq(false)
  end

  it 'C-07-12: propagates an unexpected signing exception unchanged', :aggregate_failures do
    error = RuntimeError.new('fixture signing error')
    allow(ACME).to receive(:system).with(a_string_matching(/\A\s*acme_tiny\b/)).and_raise(error)
    expect { ACME.sign(domain) }.to raise_error { |raised| expect(raised).to equal(error) }
    expect_certificates('old-cert', 'old-key')
  end
end
