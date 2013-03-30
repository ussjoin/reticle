#!/usr/bin/ruby

require 'rubygems'
require 'eventmachine'
require 'em-http'
require 'json'
require 'net/http'
require 'openssl'
require 'base64'

PIDPATH = File.dirname(__FILE__)+"/working/client/client.pid"

BASEURL =  'http://127.0.0.1:50121/reticle/'
FEEDURL = BASEURL+'_changes?feed=continuous'

MISSIONID = "mission"
CLIENTID = "client"

VIEWURL = BASEURL+"_design/utilities/"
NODEVIEWURL = VIEWURL+"_view/nodes"

REPLICATORURL = 'http://127.0.0.1:50121/_replicator/'

#This is the CA's public key, used to verify missions.
CACERTPATH = File.dirname(__FILE__)+"/certs/ca.pem"

MYCERTPATH = File.dirname(__FILE__)+"/certs/my.pem"
MYKEYPATH = File.dirname(__FILE__)+"/certs/my.key"

MISSIONPATH = File.dirname(__FILE__)+"/working/client/mission.rb"
ONIONPATH = File.dirname(__FILE__)+"/working/tor/hidden/hostname"

@runningthread = nil
@since = 0
@myaddress = nil
@mycert = nil
@mykey = nil

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
  cert = OpenSSL::X509::Certificate.new File.read CACERTPATH
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


#BaseURL: of the form "http://hostname.onion:40120/reticle/"
def insert_my_node_document(baseurl)
  #Node document has the following fields:
  #cert - My PEM certificate
  #address - My .onion address
  #signature - signature over (rev+address+cert), signed by the cert in cert
  
  puts "Asked to insert my ID document to #{baseurl}"
  
  digest = OpenSSL::Digest::SHA256.new
  
  cert = File.read MYCERTPATH
  
  cert.strip!
  
  uri = URI(baseurl+"node_#{@myaddress}")
  
  req = Net::HTTP::Get.new(uri.path)
  req["content-type"] = "application/json"
  data = nil
  Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
    http.ca_file = CACERTPATH
    http.cert = @mycert
    http.key = @mykey
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    response = http.request req # Net::HTTPResponse object
    data = JSON.parse(response.body)
  end
  newrev = 1
  currentrevision = data['_rev']
  if currentrevision
    revm = data['_rev'].match(/([0-9]+)-.+/)
    oldrev = revm[1]
    
    #Wait... if _rev is here, is the whole document valid?
    #Check it, and if so, just return immediately.
    
    a = data['address']
    c = data['cert']
    s = data['signature']
    pubkey = OpenSSL::PKey::RSA.new (OpenSSL::X509::Certificate.new cert).public_key
    if (pubkey.verify(digest, Base64.decode64(s), oldrev+a+c) and a == @myaddress and c == cert)
      puts "Was asked to insert my ID to #{baseurl}, but it already had mine!"
      return
    end
    
    #Well, guess that didn't work.
    newrev = oldrev.to_i + 1
  end
  
  
  pkey = OpenSSL::PKey::RSA.new File.read MYKEYPATH
  signature = Base64.encode64(pkey.sign(digest, newrev.to_s+@myaddress+cert)).strip
  
  data = {"cert" => cert, "address" => @myaddress, "signature" => signature}
  
  if (currentrevision)
    #This allows us to push on top of old data.
    data["_rev"] = currentrevision
  end
  
  json = JSON.generate(data)

  req = Net::HTTP::Put.new(uri.path)
  req["content-type"] = "application/json"
  req.body = json
  Net::HTTP.start(uri.host, uri.port, :use_ssl => uri.scheme == 'https') do |http|
    http.ca_file = CACERTPATH
    http.cert = @mycert
    http.key = @mykey
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    response = http.request req # Net::HTTPResponse object
    puts "Response to inserting ID document at #{baseurl}: #{response.body}"
  end
  
  
end

#Looks through the database for other nodes we've heard of, 
#and checks that they have running replications.
def check_for_replications
  uri = URI(NODEVIEWURL)
  req = Net::HTTP::Get.new(uri.path)
  req["content-type"] = "application/json"
  data = nil
  Net::HTTP.start(uri.host, uri.port) do |http|
    response = http.request req # Net::HTTPResponse object
    data = JSON.parse(response.body)
  end
  
  data['rows'].each do |node|
    d = node['value']
    puts "My address: #{@myaddress} Considering: #{d['address']}"
    if (d['address'] == @myaddress)
      #This is me-- don't try to replicate to myself, it'd be dumb.
      puts "Won't replicate to myself."
      next
    else
      puts "Proceeding with replication."
    end
    
    #signature over (rev+address+cert)
    digest = OpenSSL::Digest::SHA256.new
    a = d['address']
    c = d['cert']
    s = d['signature']
    revm = d['_rev'].match(/([0-9]+)-.+/)
    rev = revm[1]
    pubkey = OpenSSL::PKey::RSA.new (OpenSSL::X509::Certificate.new c).public_key
    if pubkey.verify(digest, Base64.decode64(s), rev+a+c)
      #Then we've got a valid ID document.
      puts "Replications: Found valid ID document for #{a}"
      
      #Now do two things: 1) Push my ID doc to it, and 2) Make sure a replication is running *from* it.
      
      #BaseURL: of the form "http://hostname.onion:34214/reticle/"
      
      remoteaddress = "https://#{a}:34214/reticle/"
      
      insert_my_node_document(remoteaddress)
      
      
      puts "Got here"
      
      uri = URI(REPLICATORURL+"rep_#{a}")
      req = Net::HTTP::Get.new(uri.path)
      req["content-type"] = "application/json"
      crepdata = nil
      Net::HTTP.start(uri.host, uri.port) do |http|
        response = http.request req # Net::HTTPResponse object
        crepdata = JSON.parse(response.body)
      end
      
      if crepdata['_replication_state'] == "triggered"
        #Then we've got a valid, working replication already.
        puts "I already have a replication for #{remoteaddress}."
        next
      end
      
      repdata = JSON.generate({
        "source" => remoteaddress,
        "continuous" => true,
        "target" => "reticle"
      })
      
      if crepdata['_rev'] #And, importantly, if we're still here...
        #This means that the replication isn't working.
        repdata['_rev'] = crepdata['_rev'] #Make it rewrite correctly
      end
      
      uri = URI(REPLICATORURL+"rep_#{a}")
      req = Net::HTTP::Put.new(uri.path)
      req["content-type"] = "application/json"
      req.body = repdata
      Net::HTTP.start(uri.host, uri.port) do |http|
        response = http.request req # Net::HTTPResponse object
        puts "Response to inserting replication document for #{remoteaddress}: #{response.body}"
      end
    else
      puts "Replications: Invalid ID document for #{a}, disregarding."
    end
    
  end
end

#Checks to see if the DB exists; if not, creates it.
def initialize_database
  uri = URI(BASEURL)
  req = Net::HTTP::Get.new(uri.path)
  req["content-type"] = "application/json"
  data = nil
  Net::HTTP.start(uri.host, uri.port) do |http|
    response = http.request req # Net::HTTPResponse object
    data = JSON.parse(response.body)
  end
  
  if data['error']
    #Well then, the DB must not be there.
    req = Net::HTTP::Put.new(uri.path)
    req["content-type"] = "application/json"
    data = nil
    Net::HTTP.start(uri.host, uri.port) do |http|
      response = http.request req # Net::HTTPResponse object
      data = JSON.parse(response.body)
    end
    if (data['ok'].nil?)
      puts "ERROR: Tried to create database, but failed."
      puts "Everything's probably going to crash."
      return
    end
    
    uri = URI(BASEURL+CLIENTID)
    req = Net::HTTP::Put.new(uri.path)
    req["content-type"] = "application/json"
    req.body = JSON.generate({"script" => "", "signature" => ""})
    data = nil
    Net::HTTP.start(uri.host, uri.port) do |http|
      response = http.request req # Net::HTTPResponse object
      data = JSON.parse(response.body)
    end
    if (data['ok'].nil?)
      puts "ERROR: Tried to create database, but failed to insert the CLIENT document."
      puts "Everything's probably going to crash."
      return
    end
    
    uri = URI(BASEURL+MISSIONID)
    req = Net::HTTP::Put.new(uri.path)
    req["content-type"] = "application/json"
    req.body = JSON.generate({"script" => "", "signature" => ""})
    data = nil
    Net::HTTP.start(uri.host, uri.port) do |http|
      response = http.request req # Net::HTTPResponse object
      data = JSON.parse(response.body)
    end
    if (data['ok'].nil?)
      puts "ERROR: Tried to create database, but failed to insert the MISSION document."
      puts "Everything's probably going to crash."
      return
    end
    
    uri = URI(VIEWURL)
    req = Net::HTTP::Put.new(uri.path)
    req["content-type"] = "application/json"
    req.body = JSON.generate({"language" => "javascript", "views" => {
      "nodes" => {
        "map" => "function(doc){
          if (doc._id.match(/^node\_/))
          {
            emit(doc._id, doc);
          }
        }"
      }
    }})
    data = nil
    Net::HTTP.start(uri.host, uri.port) do |http|
      response = http.request req # Net::HTTPResponse object
      data = JSON.parse(response.body)
    end
    if (data['ok'].nil?)
      puts "ERROR: Tried to create database, but failed to insert the MISSION document."
      puts "Everything's probably going to crash."
      return
    end
    
  else
    puts "Database exists."
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

#Write my PID to the assigned file, so the Overall script can read it
File.open(PIDPATH, 'w') {|f| f.write(Process.pid) }

@mycert = OpenSSL::X509::Certificate.new File.read MYCERTPATH
@mykey = OpenSSL::PKey::RSA.new File.read MYKEYPATH

initialize_database
mainthread = Thread.new {monitor_couch}
@myaddress = File.read ONIONPATH
@myaddress.strip!
insert_my_node_document(BASEURL)

secondthread = Thread.new {
  while true
    sleep 5
    begin
      check_for_replications
    rescue Exception => e
      puts e.message  
      puts e.backtrace.join("\n")
    end
    sleep 15
  end
}

mainthread.join
secondthread.join