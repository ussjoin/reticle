#!/bin/bash

create_ca()
{
    echo "********************************************************"
    echo "** Now Creating CA. Now Creating CA. Now Creating CA. **"
    echo "********************************************************"
    echo ""
    mkdir -p reticleCA/certs
    mkdir -p reticleCA/private
    mkdir -p reticleCA/crl
    echo "0001" > reticleCA/serial
    touch reticleCA/index.txt
    
    openssl ecparam -out ./reticleCA/private/ca.key -outform PEM -name prime256v1 -genkey
    openssl req -config openssl.cnf -x509 -new -key ./reticleCA/private/ca.key -out ./reticleCA/certs/ca.pem -outform PEM -days 3650
}

if [ -z "$1" ]; then
    echo "You need to tell me how many new certificates to generate."
    exit 1;
fi


if [ ! -d "reticleCA" ]; then
    create_ca
fi

HOWMANY=$1

echo "I will now generate $HOWMANY certificate(s)."

for (( i=0; i < $HOWMANY; i++ ))
do
    COUNTER=`cat reticleCA/serial`
    mkdir -p nodeCerts
    
    echo "***************************************"
    echo "** Now creating certificate $COUNTER."
    echo "***************************************"
    echo ""

    #Generate the key.
    openssl ecparam -out nodeCerts/node_$COUNTER.key -outform PEM -name prime256v1 -genkey
 
    #Generate the CSR.
    openssl req -config openssl.cnf -new -nodes -key nodeCerts/node_$COUNTER.key -outform PEM -out nodeCerts/node_$COUNTER.req
 
    #Sign the CSR.
    openssl ca -config openssl.cnf -batch -notext -keyfile ./reticleCA/private/ca.key \
      -cert ./reticleCA/certs/ca.pem -in nodeCerts/node_$COUNTER.req -out nodeCerts/node_$COUNTER.pem

    #Delete the CSR, it's done now.
    rm nodeCerts/node_$COUNTER.req
    
done


