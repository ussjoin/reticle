#!/bin/bash

PREFIX=/tmp/crypt
 
torshutdown()
{
    PREFIX=$PREFIX; kill -s SIGINT `cat $PREFIX/working/tor/tor.pid`
}

torstartup()
{
    #-f: Use this configuration file
    PREFIX=$PREFIX; $PREFIX/tor/src/or/tor -f $PREFIX/conf/torrc
    
    check_resolv
}

check_resolv()
{
    res=`cat /etc/resolv.conf`
    
    if [ "$res" != "nameserver 127.0.0.1" ]
        then
        mv /etc/resolv.conf /etc/resolv.conf.reticlemove
        echo "nameserver 127.0.0.1" > /etc/resolv.conf
    fi
}
 
shutdown()
{
    torshutdown
    kill `cat $PREFIX/working/client/client.pid`
    PREFIX=$PREFIX; nginx -p $PREFIX/working/nginx/ -c $PREFIX/conf/nginx.conf -s quit
    PREFIX=$PREFIX; couchdb -d -n -a $PREFIX/conf/couchdb.ini -p $PREFIX/working/couchdb/couch.pid
    mv /etc/resolv.conf.reticlemove /etc/resolv.conf
    sudo iptables -t nat -D OUTPUT -p tcp -d 10.192.0.0/10 -j REDIRECT --to-ports 9040
    return $?
}
 
control_c()
# run if user hits control-c
{
    echo -en "\n*** Exiting ***\n"
    shutdown
    rm $PREFIX/working/overall.pid
    exit 0
}

startup()
{
    # First: Make the directories, if necessary
    mkdir -p $PREFIX/working/couchdb
    mkdir -p $PREFIX/working/client
    mkdir -p $PREFIX/working/nginx
    mkdir -p $PREFIX/working/tor
    
    #-b: Run in background
    #-n: Reset configuration chain (to get rid of /etc)
    #-a: Use this configuration file
    #-p: Use this PID file
    #-d: Shutdown the system
    #-o: Use this STDOUT file
    #-e: Use this STDERR file

    PREFIX=$PREFIX; couchdb -b -n -a $PREFIX/conf/couchdb.ini \
        -p $PREFIX/working/couchdb/couch.pid \
        -o $PREFIX/working/couchdb/couch.stdout \
        -e $PREFIX/working/couchdb/couch.stderr 


    #-p: Set prefix (to make relative paths work in configuration file)
    #-c: Set configuration file
    #-s: Send signal (e.g., quit)
    PREFIX=$PREFIX; nginx -p $PREFIX/working/nginx/ -c $PREFIX/conf/nginx.conf

    torstartup
    
    sudo iptables -t nat -A OUTPUT -p tcp -d 10.192.0.0/10 -j REDIRECT --to-ports 9040
    
    $PREFIX/client.rb &
    
}

reset()
{
    #Only Tor needs to be reset in case of a connection interruption.
    torshutdown
    torstartup
}
 
# trap keyboard interrupt (control-c)
trap control_c SIGINT

trap reset SIGUSR1

echo $BASHPID > $PREFIX/working/overall.pid

startup
 
# main() loop
while true; do sleep 120; check_resolv; done

