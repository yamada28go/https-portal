require_relative '../p1_helper'

RSpec.describe 'Nginx HTTP contract', :p1 do
  it 'H01: redirects standard HTTP to HTTPS with 301', :aggregate_failures do
    rendered = render_contract('default.conf.erb')
    expect(contract_lines(rendered)).to eq(contract_fixture('http.conf'))
    expect(rendered).to match(/listen\s+80;/)
    expect(rendered).to match(/server_name\s+example\.test;/)
    expect(rendered).to match(/location \/\s*\{\s*return\s+301 https:\/\/\$server_name\$request_uri;/)
    expect(rendered).not_to include('[::]:80')
  end

  it 'H02: preserves the ACME HTTP-01 exception location', :aggregate_failures do
    rendered = render_contract('default.conf.erb')
    expect(rendered).to match(%r{location /\.well-known/acme-challenge/\s*\{\s*allow all;\s*alias /var/www/default/challenges/;\s*try_files \$uri =404;\s*\}})
  end

  it 'H03: adds the IPv6 HTTP listener when enabled', :aggregate_failures do
    with_contract_env('LISTEN_IPV6' => 'true') do
      rendered = render_contract('default.conf.erb')
      expect(rendered).to match(/listen\s+80;/)
      expect(rendered).to match(/listen\s+\[::\]:80;/)
    end
  end

  it 'H04: characterizes the omitted custom HTTPS port in the HTTP redirect', :aggregate_failures do
    rendered = render_contract('default.conf.erb', 'example.test:4443')
    expect(rendered).to match(/return\s+301 https:\/\/\$server_name\$request_uri;/)
    expect(rendered).not_to include(':4443')
  end
end
