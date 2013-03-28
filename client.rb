require 'rubygems'
require 'eventmachine'
require 'em-http'
require 'json'
require 'net/http'
require 'openssl'
require 'base64'
 
BASEURL =  'http://localhost:50121/reticle/'
FEEDURL = BASEURL+'_changes?feed=continuous'

MISSIONID = "mission"

#This is the CA's public key, used to verify missions.
CERTPATH = File.dirname(__FILE__)+"/certs/ca.pem"

MISSIONPATH = File.dirname(__FILE__)+"/working/client/mission.rb"

@runningthread = nil

@since = 0

def spawn(script)
  if (@runningthread)
    @runningthread.kill
  end
  File.open(MISSIONPATH, 'w') {|f| f.write(script) }
  @runningthread = Thread.new {system("ruby "+MISSIONPATH)}
end

def verify_mission(revision, script, signature)
  digest = OpenSSL::Digest::SHA256.new
  cert = OpenSSL::X509::Certificate.new File.read CERTPATH
  pkey = OpenSSL::PKey::RSA.new cert.public_key
  
  revm = revision.match(/([0-9]+)-.+/)
  revnumber = revm[1]
  
  pkey.verify(digest, Base64.decode64(signature), revnumber+script)
end

def handle_change(change)
  seq = change['seq']
  id = change['id']
  rev = change['changes'][0]['rev']
  @since = seq
  
  if (id == MISSIONID)
    puts "#{seq}: #{id} at #{rev}"
    uri = URI(BASEURL+MISSIONID+"?rev="+rev)
    req = Net::HTTP::Get.new(uri.path)
    req["content-type"] = "application/json"
    data = nil
    Net::HTTP.start(uri.host, uri.port) do |http|
      response = http.request req # Net::HTTPResponse object
      data = JSON.parse(response.body)
      if verify_mission(data['_rev'], data['script'], data['signature'])
        puts "Revision #{data['_rev']} validates."
        spawn(data['script'])
      else
        puts "Bad mission came in: \n#{change}\n\n"
      end
    end
  end
end
 
def monitor_couch
 
  EventMachine.run do
    http = EventMachine::HttpRequest.new(FEEDURL+"&since=#{@since}").get :timeout => 0
    buffer = ""
 
    http.errback {
      puts "Connection dropped (restarting; this is normal)"
      monitor_couch 
    }
    http.callback {
      monitor_couch  
    }
    http.stream do |chunk|
      buffer += chunk
      while line = buffer.slice!(/.+\r?\n/)
        begin
          handle_change JSON.parse(line)
        rescue
          puts "Invalid JSON: #{line}"
         end
      end
    end
  end
 
end
 
monitor_couch