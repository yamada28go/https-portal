require_relative '../p1_helper'

RSpec.describe 'Certificate renewal decisions', :p1 do
  let(:domain) { Domain.new('example.test') }

  before do
    allow(NAConfig).to receive(:force_renew?).and_return(false)
    allow(NAConfig).to receive(:renew_margin_days).and_return(30)
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(domain.key_path).and_return(true)
    allow(File).to receive(:exist?).with(domain.signed_cert_path).and_return(true)
    allow(OpenSSL).to receive(:dummy?).with(domain.signed_cert_path).and_return(false)
    allow(OpenSSL).to receive(:expires_in_days).with(domain.signed_cert_path).and_return(31)
  end

  it 'C01: signs when the private key is missing' do
    allow(File).to receive(:exist?).with(domain.key_path).and_return(false)
    expect(OpenSSL.need_to_sign_or_renew?(domain)).to eq(true)
  end

  it 'C02: signs when the signed certificate is missing' do
    allow(File).to receive(:exist?).with(domain.signed_cert_path).and_return(false)
    expect(OpenSSL.need_to_sign_or_renew?(domain)).to eq(true)
  end

  it 'C03: replaces a dummy certificate' do
    allow(OpenSSL).to receive(:dummy?).with(domain.signed_cert_path).and_return(true)
    expect(OpenSSL.need_to_sign_or_renew?(domain)).to eq(true)
  end

  it 'C04: skips renewal with 31 days left and a 30-day margin' do
    expect(OpenSSL.need_to_sign_or_renew?(domain)).to eq(false)
  end

  it 'C05: renews at exactly the 30-day margin' do
    allow(OpenSSL).to receive(:expires_in_days).with(domain.signed_cert_path).and_return(30)
    expect(OpenSSL.need_to_sign_or_renew?(domain)).to eq(true)
  end

  it 'C06: renews with 29 days left' do
    allow(OpenSSL).to receive(:expires_in_days).with(domain.signed_cert_path).and_return(29)
    expect(OpenSSL.need_to_sign_or_renew?(domain)).to eq(true)
  end

  it 'C07: honors forced renewal even with 31 days left' do
    allow(NAConfig).to receive(:force_renew?).and_return(true)
    expect(OpenSSL.need_to_sign_or_renew?(domain)).to eq(true)
  end

  it 'C08: computes remaining days relative to a fixed date' do
    allow(OpenSSL).to receive(:expires_in_days).and_call_original
    allow(Date).to receive(:today).and_return(Date.new(2024, 2, 28))
    allow(OpenSSL).to receive(:expires_at).with(domain.signed_cert_path).and_return(Date.new(2024, 3, 29))
    expect(OpenSSL.expires_in_days(domain.signed_cert_path)).to eq(30)
  end
end
