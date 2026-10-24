require_relative '../p1_helper'

RSpec.describe 'Nginx TLS configuration contract', :p1 do
  it 'T01: enables exactly TLS 1.2 and TLS 1.3', :aggregate_failures do
    rendered = render_contract('nginx.conf.erb')
    expect(contract_lines(rendered).grep(/\Assl_protocols /)).to eq(['ssl_protocols TLSv1.2 TLSv1.3;'])
  end

  it 'T02: renders the SSL port, domain and certificate paths', :aggregate_failures do
    rendered = render_contract('default.ssl.conf.erb', 'example.test:4443')
    expect(rendered).to include('listen 4443 ssl;', 'server_name example.test;')
    expect(rendered).to include('ssl_certificate /var/lib/https-portal/example.test/local/chained.crt;')
    expect(rendered).to include('ssl_certificate_key /var/lib/https-portal/example.test/local/domain.key;')
    expect(rendered).to include('ssl_dhparam /var/lib/https-portal/dhparam.pem;')
    expect(rendered).not_to include('listen [::]')
  end

  it 'T03: emits HSTS only when max-age is configured', :aggregate_failures do
    expect(render_contract('default.ssl.conf.erb')).not_to match(/add_header\s+Strict-Transport-Security/)
    with_contract_env('HSTS_MAX_AGE' => '31536000') do
      expect(render_contract('default.ssl.conf.erb')).to include('add_header Strict-Transport-Security "max-age=31536000" always;')
    end
    expect(render_contract('default.ssl.conf.erb')).not_to match(/add_header\s+Strict-Transport-Security/)
  end

  it 'T04: rejects TLS handshakes in the default SSL server', :aggregate_failures do
    rendered = render_contract('nginx.conf.erb')
    expect(rendered).to match(/server\s*\{\s*listen\s+443 ssl default_server;\s*ssl_reject_handshake on;\s*\}/)
  end
end
