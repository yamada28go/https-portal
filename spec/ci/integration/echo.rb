require 'json'
require 'webrick'

$stdout.sync = true
server = WEBrick::HTTPServer.new(
  BindAddress: '0.0.0.0', Port: 8080, AccessLog: [],
  Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
)
server.mount_proc('/') do |request, response|
  response['Content-Type'] = 'application/json'
  response.body = JSON.generate(
    service: 'https-portal-it-echo', path: request.path, query: request.query_string,
    host: request['host'], forwarded_proto: request['x-forwarded-proto'],
    forwarded_for: request['x-forwarded-for'], real_ip: request['x-real-ip']
  )
end
trap('TERM') { server.shutdown }
trap('INT') { server.shutdown }
server.start
