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
CLIENTID = "client"

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

def client_restart(script)
  puts "I am going to restart.\n\n\n"
  File.open(__FILE__, 'w') {|f| f.write(script) }
  exec("ruby "+__FILE__)
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
  if (id == MISSIONID or id == CLIENTID)
    puts "#{seq}: #{id} at #{rev}"
    uri = URI(BASEURL+id+"?rev="+rev)
    req = Net::HTTP::Get.new(uri.path)
    req["content-type"] = "application/json"
    data = nil
  
    Net::HTTP.start(uri.host, uri.port) do |http|
      response = http.request req # Net::HTTPResponse object
      data = JSON.parse(response.body)
    end
    if verify_mission(data['_rev'], data['script'], data['signature'])
      if (id == MISSIONID)
        #We always spawn on client startup, because we always want the most recent mission running.
        puts "Spawning script from #{data['_id']}."
        spawn(data['script'])
      elsif (id == CLIENTID)
        currdigest = Base64.encode64(OpenSSL::Digest::SHA256.new.digest(File.read __FILE__)).strip
        newdigest = Base64.encode64(OpenSSL::Digest::SHA256.new.digest(data['script'])).strip
        #We don't respawn if it's the same, as that would cause an infinite loop.
        if currdigest != newdigest
          puts "Current digest = '#{currdigest}'"
          puts "New digest     = '#{newdigest}'"
          client_restart(data['script'])
        else
          puts "Got new client in; same as current client, so ignoring it."
        end
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
        rescue Exception => e
          puts "Caught exception when processing #{line}"
          puts e.message  
          puts e.backtrace.join("\n")
         end
      end
    end
  end
 
end
 
puts "====================="
puts "=Client Starting Up ="
puts "====================="
 
monitor_couch

