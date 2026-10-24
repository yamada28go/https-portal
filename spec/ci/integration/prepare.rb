require 'digest'
require 'fileutils'
require 'json'
require 'openssl'
require 'securerandom'

scenario = ENV.fetch('IT_SCENARIO')
# Public test-only DH parameters: RFC 3526 section 3, MODP group 14.
# https://www.rfc-editor.org/rfc/rfc3526.html#section-3
# Avoid probabilistic safe-prime generation on every isolated portal startup.
prime_hex = <<~HEX.delete(" \n")
  FFFFFFFF FFFFFFFF C90FDAA2 2168C234 C4C6628B 80DC1CD1
  29024E08 8A67CC74 020BBEA6 3B139B22 514A0879 8E3404DD
  EF9519B3 CD3A431B 302B0A6D F25F1437 4FE1356D 6D51C245
  E485B576 625E7EC6 F44C42E9 A637ED6B 0BFF5CB6 F406B7ED
  EE386BFB 5A899FA5 AE9F2411 7C4B1FE6 49286651 ECE45B3D
  C2007CB8 A163BF05 98DA4836 1C55D39A 69163FA8 FD24CF5F
  83655D23 DCA3AD96 1C62F356 208552BB 9ED52907 7096966D
  670C354E 4ABC9804 F1746C08 CA18217C 32905E46 2E36CE3B
  E39E772C 180E8603 9B2783A2 EC07A28F B5C55DF0 6F4C52C9
  DE2BCBF6 95581718 3995497C EA956AE5 15D22618 98FA0510
  15728E5A 8AACAA68 FFFFFFFF FFFFFFFF
HEX
parameters = OpenSSL::ASN1::Sequence.new([
  OpenSSL::ASN1::Integer.new(OpenSSL::BN.new(prime_hex, 16)),
  OpenSSL::ASN1::Integer.new(2)
])
dh = OpenSSL::PKey::DH.new(parameters.to_der)
raise 'Invalid test DH parameters' unless dh.params_ok?
FileUtils.mkdir_p('/fixture/certificates')
File.write('/fixture/certificates/dhparam.pem', dh.to_pem)

public_dir = '/fixture/public'
FileUtils.mkdir_p(public_dir)
File.chmod(0777, public_dir)
if scenario == 'static'
  dir = '/fixture/site/static.test'
  FileUtils.mkdir_p(File.join(dir, 'nested'))
  File.write(File.join(dir, 'index.html'), "HTTPS-PORTAL integration index\n")
  File.write(File.join(dir, 'nested/page.txt'), "HTTPS-PORTAL integration nested page\n")
end

def make_certificate(name, key, issuer = nil, issuer_key = nil, ca: false, pathlen: nil, days: 90)
  cert = OpenSSL::X509::Certificate.new
  cert.version = 2
  cert.serial = SecureRandom.random_number(2**120) + 1
  cert.subject = OpenSSL::X509::Name.parse("/CN=#{name}")
  cert.issuer = issuer ? issuer.subject : cert.subject
  cert.public_key = key.public_key
  cert.not_before = Time.now - 60
  cert.not_after = Time.now + days * 86400
  factory = OpenSSL::X509::ExtensionFactory.new
  factory.subject_certificate = cert
  factory.issuer_certificate = issuer || cert
  constraints = ca ? "CA:TRUE,pathlen:#{pathlen}" : 'CA:FALSE'
  cert.add_extension(factory.create_extension('basicConstraints', constraints, true))
  cert.add_extension(factory.create_extension('keyUsage', ca ? 'keyCertSign,cRLSign' : 'digitalSignature,keyEncipherment', true))
  cert.add_extension(factory.create_extension('subjectKeyIdentifier', 'hash'))
  cert.add_extension(factory.create_extension('authorityKeyIdentifier', 'keyid:always'))
  unless ca
    cert.add_extension(factory.create_extension('extendedKeyUsage', 'serverAuth'))
    cert.add_extension(factory.create_extension('subjectAltName', "DNS:#{name}"))
  end
  cert.sign(issuer_key || key, OpenSSL::Digest::SHA256.new)
  cert
end

if scenario == 'ca'
  root_key = OpenSSL::PKey::RSA.new(2048)
  root = make_certificate('Integration Root CA', root_key, ca: true, pathlen: 1, days: 730)
  intermediate_key = OpenSSL::PKey::RSA.new(2048)
  intermediate = make_certificate('Integration Intermediate CA', intermediate_key, root, root_key, ca: true, pathlen: 0, days: 365)
  leaf_key = OpenSSL::PKey::RSA.new(2048)
  leaf = make_certificate('tls.test', leaf_key, intermediate, intermediate_key)
  wrong_key = OpenSSL::PKey::RSA.new(2048)
  wrong_root = make_certificate('Unrelated Integration CA', wrong_key, ca: true, pathlen: 1, days: 730)
  raise 'Generated leaf/key mismatch' unless leaf.public_key.to_der == leaf_key.public_key.to_der
  dir = '/fixture/certificates/tls.test/local'
  FileUtils.mkdir_p(dir)
  File.write(File.join(dir, 'signed.crt'), leaf.to_pem + intermediate.to_pem)
  # Nginx reads chained.crt; existing certificates bypass product chain_certs.
  File.symlink('signed.crt', File.join(dir, 'chained.crt'))
  File.write(File.join(dir, 'domain.key'), leaf_key.to_pem)
  File.chmod(0600, File.join(dir, 'domain.key'))
  File.write(File.join(public_dir, 'root-ca.crt'), root.to_pem)
  File.write(File.join(public_dir, 'wrong-ca.crt'), wrong_root.to_pem)
  File.write(File.join(public_dir, 'expected.json'), JSON.generate(
    leaf_sha256: Digest::SHA256.hexdigest(leaf.to_der),
    intermediate_sha256: Digest::SHA256.hexdigest(intermediate.to_der)
  ))
end
# CA/intermediate private keys are never written to a volume or stdout.
puts JSON.generate(result: 'prepared', scenario: scenario)
