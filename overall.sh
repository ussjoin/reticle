#!/bin/bash

PREFIX=/tmp/crypt
 
torshutdown()
{
    PREFIX=$PREFIX; kill -s SIGINT `cat $PREFIX/working/tor/tor.pid`
}

torstartup()
{
    #-f: Use this configuration file
    PREFIX=$PREFIX; tor -f $PREFIX/conf/torrc
}
 
shutdown()
{
    torshutdown
    PREFIX=$PREFIX; nginx -p $PREFIX/working/nginx/ -c $PREFIX/conf/nginx.conf -s quit
    PREFIX=$PREFIX; couchdb -d -n -a $PREFIX/conf/couchdb.ini -p $PREFIX/working/couchdb/couch.pid
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
while true; do sleep 1; done

