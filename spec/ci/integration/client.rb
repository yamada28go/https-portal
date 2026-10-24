require 'digest'
require 'json'
require 'net/http'
require 'openssl'
require 'socket'
require 'timeout'

module IntegrationClient
  class NotReady < StandardError; end
  class ContractFailure < StandardError; end
  TRANSIENT = [NotReady, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Timeout::Error, Net::HTTPBadResponse].freeze

  def self.assert(condition, message)
    raise ContractFailure, message unless condition
  end

  class Client
    attr_reader :host, :cert, :client_ip
    def initialize(host, root: nil)
      raise 'Unexpected host' unless %w[portal.test proxy.test auth.test tls.test static.test ip.test ip-auth.test].include?(host)
      @host = host
      @root = root
    end

    def tls(store: nil, check_host: @host, sni: @host)
      tcp = nil
      ssl = nil
      Timeout.timeout(10) do
        begin
          tcp = TCPSocket.new(@host, 443)
          @client_ip = tcp.addr[3]
          context = OpenSSL::SSL::SSLContext.new
          context.verify_mode = store ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
          context.cert_store = store if store
          ssl = OpenSSL::SSL::SSLSocket.new(tcp, context)
          ssl.hostname = sni
          ssl.connect
          ssl.post_connection_check(check_host) if store
          { cert: ssl.peer_cert, chain: ssl.peer_cert_chain || [] }
        ensure
          begin
            ssl.close if ssl
          ensure
            tcp.close if tcp && !tcp.closed?
          end
        end
      end
    end

    def store_for(pem)
      store = OpenSSL::X509::Store.new
      store.add_cert(OpenSSL::X509::Certificate.new(pem))
      store
    end

    def establish_trust
      if @root
        @store = store_for(File.read(@root))
        @cert = tls(store: @store)[:cert]
      else
        # Only bootstrap the isolated local fixture; later requests verify TLS.
        @cert = tls[:cert]
        raise NotReady, 'Expected hostname is not ready' unless OpenSSL::SSL.verify_certificate_identity(@cert, @host)
        raise NotReady, 'Expected local self-signed certificate' unless @cert.issuer == @cert.subject && @cert.verify(@cert.public_key)
        raise NotReady, 'Certificate is outside validity' unless @cert.not_before <= Time.now && Time.now < @cert.not_after
        @store = store_for(@cert.to_pem)
        tls(store: @store)
      end
    end

    def request(path = '/', secure: true, credentials: nil, headers: {})
      Timeout.timeout(10) do
        http = Net::HTTP.new(@host, secure ? 443 : 80, nil)
        if secure
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.cert_store = @store
          # Ruby 2.7.2 Net::HTTP checks hostname after the verified handshake.
        end
        http.open_timeout = 5
        http.read_timeout = 5
        req = Net::HTTP::Get.new(path)
        headers.each { |name, value| req[name] = value }
        req.basic_auth(*credentials) if credentials
        http.request(req)
      end
    end

    def ready!(seconds)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      last = nil
      stable = 0
      fingerprint = nil
      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        break if remaining <= 0
        begin
          Timeout.timeout([remaining, 10].min) do
            establish_trust
            response = request
            raise NotReady, 'HTTP listener not ready' unless %w[200 401].include?(response.code)
            current = sha256
            stable = (current == fingerprint) ? stable + 1 : 1
            fingerprint = current
          end
          return self if stable >= 3
        rescue *TRANSIENT => error
          stable = 0
          last = "#{error.class}: #{error.message}"
        end
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sleep [remaining, 1].min if remaining > 0
      end
      raise NotReady, "Readiness timed out after #{seconds}s: #{last}"
    end

    def sha256
      Digest::SHA256.hexdigest(@cert.to_der)
    end

    def current_tls
      tls(store: @store)
    end
  end
end
