require_relative '../p1_helper'

RSpec.describe 'Nginx routing configuration contract', :p1 do
  it 'R01: serves a static site without proxying', :aggregate_failures do
    rendered = render_contract('default.ssl.conf.erb')
    expect(rendered).to match(%r{root\s+/var/www/vhosts/example\.test;})
    expect(rendered).to match(/index\s+index\.html;/)
    expect(rendered).not_to include('proxy_pass', 'upstream backend_', 'return    307')
  end

  it 'R02: proxies HTTP with Host and forwarding headers', :aggregate_failures do
    rendered = render_contract('default.ssl.conf.erb', 'example.test -> http://upstream.test:8000')
    expect(contract_lines(rendered).grep(/\Aproxy_/)).to eq(contract_fixture('proxy-directives.conf'))
    expect(rendered).to include('proxy_pass http://upstream.test:8000;')
    expect(rendered).to include('proxy_set_header Host $host;', 'proxy_set_header X-Real-IP $remote_addr;')
    expect(rendered).to include('proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;', 'proxy_set_header X-Forwarded-Proto $scheme;')
    expect(rendered).not_to include('proxy_http_version', 'proxy_set_header Upgrade', 'proxy_set_header Connection', 'set $backend')
  end

  it 'R03: renders ordered upstreams with parameters and a backend reference', :aggregate_failures do
    rendered = render_contract('default.ssl.conf.erb', 'example.test -> https://target1.test:8000|target2.test:8001[backup max_conns=100]')
    expect(rendered).to match(/upstream backend_example\.test\s*\{\s*server target1\.test:8000\s*;\s*server target2\.test:8001 backup max_conns=100;\s*\}/)
    expect(rendered).to include('proxy_pass https://backend_example.test;')
  end

  it 'R04: redirects HTTPS to the target with the default 307', :aggregate_failures do
    rendered = render_contract('default.ssl.conf.erb', 'example.test => target.test')
    expect(rendered).to match(/return\s+307 https:\/\/target\.test\$request_uri;/)
    expect(rendered).not_to include('proxy_pass')
  end

  it 'R05: honors an explicit HTTPS redirect code', :aggregate_failures do
    with_contract_env('REDIRECT_CODE' => '308') do
      rendered = render_contract('default.ssl.conf.erb', 'example.test => https://target.test')
      expect(rendered).to match(/return\s+308 https:\/\/target\.test\$request_uri;/)
      expect(rendered).not_to match(/return\s+307 /)
    end
  end

  it 'R06: enables websocket headers and the matching global map', :aggregate_failures do
    with_contract_env('WEBSOCKET' => 'true') do
      rendered = render_contract('default.ssl.conf.erb', 'example.test -> http://upstream.test')
      expect(rendered).to include('proxy_http_version 1.1;', 'proxy_set_header Upgrade $http_upgrade;', 'proxy_set_header Connection $connection_upgrade;')
      expect(render_contract('nginx.conf.erb')).to match(/map \$http_upgrade \$connection_upgrade\s*\{\s*default upgrade;\s*''\s+close;\s*\}/)
    end
    expect(render_contract('nginx.conf.erb')).not_to include('map $http_upgrade')
  end

  it 'R07: uses a runtime backend variable for dynamic upstreams', :aggregate_failures do
    with_contract_env('DYNAMIC_UPSTREAM' => 'true') do
      rendered = render_contract('default.ssl.conf.erb', 'example.test -> http://upstream.test:8000')
      expect(rendered).to include('set $backend http://upstream.test:8000;', 'proxy_pass $backend;')
      expect(rendered).not_to include('proxy_pass http://upstream.test:8000;')
    end
  end
end
