#!/bin/bash

PREFIX=/tmp/crypt
 
cleanup()
{
  #rm -f /tmp/tempfile
  PREFIX=$PREFIX; couchdb -d -n -a $PREFIX/conf/couchdb.ini -p $PREFIX/working/couchdb/couch.pid
  PREFIX=$PREFIX; nginx -p $PREFIX/working/nginx/ -c $PREFIX/conf/nginx.conf -s quit
  return $?
}
 
control_c()
# run if user hits control-c
{
  echo -en "\n*** Exiting ***\n"
  cleanup
  exit $?
}
 
# trap keyboard interrupt (control-c)
trap control_c SIGINT
 

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
 
# main() loop
while true; do sleep 1; done