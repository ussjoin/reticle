require 'rubygems'
require 'json'
require 'openssl'
require 'trollop'
require 'base64'
require 'net/http'

PKEYPATH = File.dirname(__FILE__)+"/../certs/ca.key"
BASEURL = "http://localhost:50121/reticle/"
MISSIONURI = URI(BASEURL+"mission")
CLIENTURI = URI(BASEURL+"client")

# Signature format: Revision NUMBER ONLY (i.e., 12, not 12-asfdgfhdasdjfhnf), immediately followed by script.
# The number is for the revision the new script will be.
# This is to prevent rollback attacks (by an attacker pushing an old script to stop a new script running).

def signstuff(revision, data, pkeypath)
  digest = OpenSSL::Digest::SHA256.new
  pkey = OpenSSL::PKey::RSA.new File.read pkeypath

  revm = revision.match(/([0-9]+)-.+/)
  oldrev = revm[1]
  newrev = oldrev.to_i + 1

  signature = Base64.encode64(pkey.sign(digest, newrev.to_s+data))
end

def pushstuff(rev, data, signature)
  json = JSON.generate({"script" => data, "signature" => signature, "_rev" => rev})
  req = Net::HTTP::Put.new(MISSIONURI.path)
  req["content-type"] = "application/json"
  req.body = json
  Net::HTTP.start(MISSIONURI.host, MISSIONURI.port) do |http|
    response = http.request req # Net::HTTPResponse object
    puts response.body
  end
end

def pushclient(rev, data, signature)
  json = JSON.generate({"script" => data, "signature" => signature, "_rev" => rev,
    "digest" => Base64.encode64(OpenSSL::Digest::SHA256.new.digest(data)).strip})
  req = Net::HTTP::Put.new(CLIENTURI.path)
  req["content-type"] = "application/json"
  req.body = json
  Net::HTTP.start(CLIENTURI.host, CLIENTURI.port) do |http|
    response = http.request req # Net::HTTPResponse object
    puts response.body
  end
end

def checkrevision(isclient)
  
  uri = MISSIONURI
  if (isclient)
    uri = CLIENTURI
  end
  
  req = Net::HTTP::Get.new(uri.path)
  req["content-type"] = "application/json"
  data = nil
  Net::HTTP.start(uri.host, uri.port) do |http|
    response = http.request req # Net::HTTPResponse object
    data = JSON.parse(response.body)
  end
  data['_rev']
end


opts = Trollop::options do
  banner <<-HEREBEDRAGONS
  
Command.rb sends commands into your Reticle CouchDB.

Usage:
  command.rb [options]
where [options] are:

HEREBEDRAGONS
  
  opt :commandfile, "Path to the file you wish to push to the Reticle CouchDB", :type => :io, :required => true
  opt :privatekey, "Path to the private key that will sign the command", :type => :string, :default => PKEYPATH
  opt :client, "Set this if you're pushing an updated client script, rather than the normal script." #default false
end

data = File.read(opts[:commandfile])

rev = checkrevision(opts[:client])

sig = signstuff(rev, data, opts[:privatekey])

if (opts[:client])
  pushclient(rev, data, sig)
else
  pushstuff(rev, data, sig)
end
