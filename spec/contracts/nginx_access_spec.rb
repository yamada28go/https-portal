require_relative '../p1_helper'

RSpec.describe 'Nginx access configuration contract', :p1 do
  it 'A01: references the Basic authentication password file', :aggregate_failures do
    rendered = render_contract('default.ssl.conf.erb', 'fixture-user:fixture-secret@example.test')
    expect(rendered).to include('auth_basic "Password";')
    expect(rendered).to include('auth_basic_user_file /var/lib/https-portal/example.test/local/htaccess;')
  end

  it 'A02: omits authentication directives when credentials are absent', :aggregate_failures do
    rendered = render_contract('default.ssl.conf.erb')
    expect(contract_lines(rendered).grep(/\Aauth_basic(?:\s|_)/)).to be_empty
    expect(contract_lines(rendered).grep(/\A(?:allow|deny) /)).to be_empty
  end

  it 'A03: allows one CIDR before denying all other clients', :aggregate_failures do
    rendered = render_contract('default.ssl.conf.erb', '[192.0.2.0/24]example.test')
    expect(contract_lines(rendered).grep(/\A(?:allow|deny) /)).to eq(['allow 192.0.2.0/24;', 'deny all;'])
  end

  it 'A04: preserves the allow-list order before deny all', :aggregate_failures do
    rendered = render_contract('default.ssl.conf.erb', '[ 192.0.2.10 198.51.100.0/24 ]example.test')
    expect(contract_lines(rendered).grep(/\A(?:allow|deny) /)).to eq([
      'allow 192.0.2.10;', 'allow 198.51.100.0/24;', 'deny all;'
    ])
  end

  it 'A05: keeps plaintext credentials out of generated configuration', :aggregate_failures do
    rendered = render_contract('default.ssl.conf.erb', 'fixture-user:fixture-secret@example.test -> http://upstream.test')
    expect(rendered).to include('auth_basic_user_file /var/lib/https-portal/example.test/local/htaccess;')
    expect(rendered).not_to include('fixture-user', 'fixture-secret')
  end
end
