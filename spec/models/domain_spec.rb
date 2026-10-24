require_relative '../p1_helper'

RSpec.describe Domain, :p1 do
  keys = [:descriptor, :name, :env_format_name, :upstream_proto, :upstreams, :redirect_target_url, :stage, :basic_auth_username, :basic_auth_password, :access_restriction, :port]

  domain_configs = [
      ['example.com', 'example.com', 'EXAMPLE_COM', nil, [], nil, 'local', nil, nil, nil, "443"],
      ['example.com:4443', 'example.com', 'EXAMPLE_COM', nil, [], nil, 'local', nil, nil, nil, "4443"],
      ['4example.com', '4example.com', '4EXAMPLE_COM', nil, [], nil, 'local', nil, nil, nil, "443"],
      [' example.com ', 'example.com', 'EXAMPLE_COM', nil, [], nil, 'local', nil, nil, nil, "443"],
      ['example.com #staging', 'example.com', 'EXAMPLE_COM', nil, [], nil, 'staging', nil, nil, nil, "443"],
      ['example.com -> http://target ', 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target', :parameters => nil}], nil, 'local', nil, nil, nil, "443"],
      ["example.com \n-> http://target \n", 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target', :parameters => nil}], nil, 'local', nil, nil, nil, "443"],
      ["example.com\n-> http://target ", 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target', :parameters => nil}], nil, 'local', nil, nil, nil, "443"],
      ['example.com -> http://target:8000', 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target:8000', :parameters => nil}], nil, 'local', nil, nil, nil, "443"],
      ['example.com -> target:8000', 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target:8000', :parameters => nil}], nil, 'local', nil, nil, nil, "443"],
      ['example.com => http://target', 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target', :parameters => nil}], 'http://target', 'local', nil, nil, nil, "443"],
      ['example.com => https://target', 'example.com', 'EXAMPLE_COM', 'https://', [{:address => 'target', :parameters => nil}], 'https://target', 'local', nil, nil, nil, "443"],
      ['example.com => target', 'example.com', 'EXAMPLE_COM', 'https://', [{:address => 'target', :parameters => nil}], 'https://target', 'local', nil, nil, nil, "443"],
      ['example.com=>http://target', 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target', :parameters => nil}], 'http://target', 'local', nil, nil, nil, "443"],
      ['example.com -> http://target #staging', 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target', :parameters => nil}], nil, 'staging', nil, nil, nil, "443"],
      ['example.com => http://target #staging', 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target', :parameters => nil}], 'http://target', 'staging', nil, nil, nil, "443"],
      ['example.com->http://target #staging', 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target', :parameters => nil}], nil, 'staging', nil, nil, nil, "443"],
      ['exam-ple.com->http://tar-get #staging', 'exam-ple.com', 'EXAM_PLE_COM', 'http://', [{:address => 'tar-get', :parameters => nil}], nil, 'staging', nil, nil, nil, "443"],
      ['example_.com->http://target #staging', 'example_.com', 'EXAMPLE__COM', 'http://', [{:address => 'target', :parameters => nil}], nil, 'staging', nil, nil, nil, "443"],
      ['example.com->http://tar_get_ #staging', 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'tar_get_', :parameters => nil}], nil, 'staging', nil, nil, nil, "443"],
      ['username:password@example.com', 'example.com', 'EXAMPLE_COM', nil, [], nil, 'local', 'username', 'password', nil, "443"],
      ['username:password@example.com -> http://target #staging', 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target', :parameters => nil}], nil, 'staging', 'username', 'password', nil, "443"],
      ['[1.2.3.4/24]username:password@example.com -> http://target #staging', 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target', :parameters => nil}], nil, 'staging', 'username', 'password', %w(1.2.3.4/24), "443"],
      [' [ 1.2.3.4 4.3.2.1/24 ] username:password@example.com -> http://target #staging', 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target', :parameters => nil}], nil, 'staging', 'username', 'password', %w(1.2.3.4 4.3.2.1/24), "443"],
      ['example.com -> https://target1|target2:8000', 'example.com', 'EXAMPLE_COM', 'https://', [{:address => 'target1', :parameters => nil}, {:address => 'target2:8000', :parameters => nil}], nil, 'local', nil, nil, nil, "443"],
      ['example.com -> http://target1:8000|target2:8001[backup max_conns=100]', 'example.com', 'EXAMPLE_COM', 'http://', [{:address => 'target1:8000', :parameters => nil}, {:address => 'target2:8001', :parameters => 'backup max_conns=100'}], nil, 'local', nil, nil, nil, "443"],
  ]

  domain_configs.each_with_index do |values, index|
    expected = Hash[keys.zip(values)]
    it format('D%02d: %s', index + 1, expected.fetch(:descriptor).inspect), :aggregate_failures do
      domain = Domain.new(expected.fetch(:descriptor))
      (keys - [:descriptor]).each do |field|
        expect(domain.public_send(field)).to eq(expected.fetch(field)), "Unexpected #{field} for #{expected.fetch(:descriptor).inspect}"
      end
    end
  end
end
