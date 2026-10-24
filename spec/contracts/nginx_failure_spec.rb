require_relative '../p1_helper'
require 'tmpdir'

RSpec.describe 'C-08: current Nginx write and reload behavior', :p1 do
  context 'reload results and process control' do
    it 'C-08-01: returns false without killing after an ordinary reload failure' do
      expect(Nginx).to receive(:system).with('nginx -s reload').and_return(false)
      expect(Nginx).not_to receive(:kill)
      expect(Nginx.reload).to eq(false)
    end

    it 'C-08-02: returns true after a successful reload' do
      expect(Nginx).to receive(:system).with('nginx -s reload').and_return(true)
      expect(Nginx).not_to receive(:kill)
      expect(Nginx.reload).to eq(true)
    end

    it 'C-08-03: preserves a nil reload result without killing by default' do
      expect(Nginx).to receive(:system).with('nginx -s reload').and_return(nil)
      expect(Nginx).not_to receive(:kill)
      expect(Nginx.reload).to be_nil
    end

    it 'C-08-04: kills on failure when requested and returns the reload result' do
      expect(Nginx).to receive(:system).with('nginx -s reload').ordered.and_return(false)
      expect(Nginx).to receive(:system).with('pkill -F /var/run/nginx.pid').ordered.and_return(true)
      expect(Nginx.reload(true)).to eq(false)
    end

    it 'C-08-05: does not kill a successful reload even when killing is enabled' do
      expect(Nginx).to receive(:system).with('nginx -s reload').and_return(true)
      expect(Nginx).not_to receive(:kill)
      expect(Nginx.reload(true)).to eq(true)
    end

    it 'C-08-06: retains nil even if the subsequent kill command returns false' do
      expect(Nginx).to receive(:system).with('nginx -s reload').ordered.and_return(nil)
      expect(Nginx).to receive(:system).with('pkill -F /var/run/nginx.pid').ordered.and_return(false)
      expect(Nginx.reload(true)).to be_nil
    end

    it 'C-08-07: propagates command exceptions without attempting to kill' do
      error = RuntimeError.new('fixture reload error')
      expect(Nginx).to receive(:system).with('nginx -s reload').and_raise(error)
      expect(Nginx).not_to receive(:kill)
      expect { Nginx.reload(true) }.to raise_error { |raised| expect(raised).to equal(error) }
    end
  end

  context 'configuration writes' do
    around do |example|
      Dir.mktmpdir('https-portal-nginx-') do |directory|
        @output_directory = directory
        example.run
      end
    end

    let(:domain) { Domain.new('example.test') }
    let(:http_path) { '/etc/nginx/conf.d/example.test.conf' }
    let(:ssl_path) { '/etc/nginx/conf.d/example.test.ssl.conf' }

    before do
      @output_paths = {
        '/etc/nginx/nginx.conf' => File.join(@output_directory, 'nginx.conf'),
        http_path => File.join(@output_directory, 'http.conf'),
        ssl_path => File.join(@output_directory, 'ssl.conf'),
        '/etc/nginx/conf.d/example.test_4443.ssl.conf' => File.join(@output_directory, 'ssl-custom.conf')
      }
      @output_paths.each_value { |path| File.binwrite(path, "previous-config\n") }
      allow(File).to receive(:exist?).and_call_original
      %w[example.test.conf.erb example.test.ssl.conf.erb].each do |name|
        allow(File).to receive(:exist?).with("/var/lib/nginx-conf/#{name}").and_return(false)
      end
      allow(ERBBinding).to receive(:new).and_wrap_original do |original, template, values|
        raise "Unexpected template path: #{template}" unless template.start_with?('/var/lib/nginx-conf/')
        original.call(File.join(ContractRenderHelpers::TEMPLATE_DIR, File.basename(template)), values)
      end
      # Execute real file operations, but redirect every production write to tmp.
      allow(File).to receive(:open).and_wrap_original do |original, *args, &block|
        if args[0].is_a?(String) && args[0].start_with?('/etc/nginx/')
          raise 'Unexpected Nginx file mode' unless args[1] == 'w'
          original.call(@output_paths.fetch(args[0]), 'w') do |file|
            allow(file).to receive(:write).and_raise(@write_error) if @write_error
            block.call(file)
          end
        else
          original.call(*args, &block)
        end
      end
      expect(Nginx).not_to receive(:system)
    end

    def written_config(path)
      File.binread(@output_paths.fetch(path))
    end

    it 'C-08-08: replaces the global config with the rendered real template', :aggregate_failures do
      Nginx.setup
      expect(written_config('/etc/nginx/nginx.conf')).to include('ssl_protocols TLSv1.2 TLSv1.3;', 'ssl_reject_handshake on;')
      expect(written_config('/etc/nginx/nginx.conf')).not_to include('previous-config')
      expect(written_config(http_path)).to eq("previous-config\n")
    end

    it 'C-08-09: writes the HTTP template to the domain config path', :aggregate_failures do
      Nginx.config_http(domain)
      expect(written_config(http_path)).to match(/return\s+301 https:\/\/\$server_name\$request_uri;/)
      expect(written_config(http_path)).to include('location /.well-known/acme-challenge/')
      expect(written_config(ssl_path)).to eq("previous-config\n")
    end

    it 'C-08-10: writes standard SSL config using the legacy filename', :aggregate_failures do
      Nginx.config_ssl(domain)
      expect(written_config(ssl_path)).to include('listen 443 ssl;', 'ssl_certificate /var/lib/https-portal/example.test/local/chained.crt;')
      expect(written_config('/etc/nginx/conf.d/example.test_4443.ssl.conf')).to eq("previous-config\n")
    end

    it 'C-08-11: writes a custom SSL port to its port-specific filename', :aggregate_failures do
      Nginx.config_ssl(Domain.new('example.test:4443'))
      expect(written_config('/etc/nginx/conf.d/example.test_4443.ssl.conf')).to include('listen 4443 ssl;')
      expect(written_config(ssl_path)).to eq("previous-config\n")
    end

    it 'C-08-12: leaves the old global config intact on a rendering exception', :aggregate_failures do
      error = RuntimeError.new('fixture render error')
      allow_any_instance_of(ERBBinding).to receive(:compile).and_raise(error)
      expect { Nginx.setup }.to raise_error { |raised| expect(raised).to equal(error) }
      expect(written_config('/etc/nginx/nginx.conf')).to eq("previous-config\n")
    end

    it 'C-08-13: leaves HTTP config truncated on a rendering exception', :aggregate_failures do
      error = RuntimeError.new('fixture render error')
      allow_any_instance_of(ERBBinding).to receive(:compile).and_raise(error)
      expect { Nginx.config_http(domain) }.to raise_error { |raised| expect(raised).to equal(error) }
      expect(written_config(http_path)).to eq('')
      expect(written_config(ssl_path)).to eq("previous-config\n")
    end

    it 'C-08-14: leaves SSL config truncated on a rendering exception', :aggregate_failures do
      error = RuntimeError.new('fixture render error')
      allow_any_instance_of(ERBBinding).to receive(:compile).and_raise(error)
      expect { Nginx.config_ssl(domain) }.to raise_error { |raised| expect(raised).to equal(error) }
      expect(written_config(ssl_path)).to eq('')
      expect(written_config(http_path)).to eq("previous-config\n")
    end

    it 'C-08-15: propagates an open error before rendering and preserves the old file', :aggregate_failures do
      allow(File).to receive(:open).with(http_path, 'w').and_raise(Errno::EACCES)
      expect(ERBBinding).not_to receive(:new)
      expect { Nginx.config_http(domain) }.to raise_error(Errno::EACCES)
      expect(written_config(http_path)).to eq("previous-config\n")
    end

    it 'C-08-16: propagates a write error and leaves the opened file truncated', :aggregate_failures do
      @write_error = Errno::ENOSPC.new('fixture disk full')
      expect { Nginx.config_http(domain) }.to raise_error { |raised| expect(raised).to equal(@write_error) }
      expect(written_config(http_path)).to eq('')
      expect(written_config(ssl_path)).to eq("previous-config\n")
    end

    it 'C-08-17: keeps the new HTTP file when subsequent SSL rendering fails', :aggregate_failures do
      error = RuntimeError.new('fixture SSL render error')
      allow(Nginx).to receive(:compiled_domain_config).and_call_original
      allow(Nginx).to receive(:compiled_domain_config).with(domain, true).and_raise(error)
      expect { Nginx.config_domain(domain) }.to raise_error { |raised| expect(raised).to equal(error) }
      expect(written_config(http_path)).to match(/return\s+301 /)
      expect(written_config(ssl_path)).to eq('')
    end

    it 'C-08-18: skips SSL configuration when HTTP rendering fails first', :aggregate_failures do
      error = RuntimeError.new('fixture HTTP render error')
      allow(Nginx).to receive(:compiled_domain_config).with(domain, false).and_raise(error)
      expect(Nginx).not_to receive(:config_ssl)
      expect { Nginx.config_domain(domain) }.to raise_error { |raised| expect(raised).to equal(error) }
      expect(written_config(http_path)).to eq('')
      expect(written_config(ssl_path)).to eq("previous-config\n")
    end
  end
end
