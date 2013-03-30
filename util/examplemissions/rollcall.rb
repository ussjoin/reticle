require 'rubygems'
require 'json'
require 'net/http'
require 'openssl'
require 'base64'

#Remember: we're at ./working/client/something.rb
CERTPATH = File.dirname(__FILE__)+"/../../certs/my.pem"
TORPATH = File.dirname(__FILE__)+"/../../working/tor/hidden/hostname"
RETICLEURL = "http://127.0.0.1:50121/reticle/"

torname = File.read TORPATH
torname.strip!

digest = OpenSSL::Digest::SHA256.new
cert = OpenSSL::X509::Certificate.new File.read CERTPATH

json = JSON.generate({"my_serial" => cert.serial, 
  "my_digest" => Base64.encode64(digest.digest(cert.to_s)).strip,
  "torname" => torname
  })


theuri = URI(RETICLEURL+"rollcall_"+cert.serial.to_s)
req = Net::HTTP::Put.new(theuri.path)
req["content-type"] = "application/json"
req.body = json
Net::HTTP.start(theuri.host, theuri.port) do |http|
  response = http.request req # Net::HTTPResponse object
  puts response.body
end
