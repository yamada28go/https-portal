require 'fileutils'
require 'openssl'
require 'json'
require 'digest'

scenario = ENV.fetch('IT_SCENARIO')
variant = ENV.fetch('IT_TLS_VARIANT')
raise 'Unexpected certificate mutation scenario' unless %w[tls-chain tls-expired].include?(scenario)
allowed = scenario == 'tls-chain' ? %w[valid missing] : %w[valid expired]
raise 'Unexpected certificate variant' unless allowed.include?(variant)
source = File.join('/fixture/certificates/.tls-fixtures', "#{variant}.crt")
target = '/fixture/certificates/tls.test/local/signed.crt'
cert = OpenSSL::X509::Certificate.new(File.read(source))
key = OpenSSL::PKey.read(File.read('/fixture/certificates/tls.test/local/domain.key'))
raise 'Fixture certificate/key mismatch' unless cert.public_key.to_der == key.public_key.to_der
FileUtils.cp(source, target)
puts JSON.generate(result: 'switched', scenario: scenario, variant: variant,
                   certificate_sha256: Digest::SHA256.hexdigest(cert.to_der))