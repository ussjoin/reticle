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
    
    openssl req -config openssl.cnf -x509 -nodes -days 3650 \
        -newkey rsa:2048 -out reticleCA/certs/ca.pem \
        -outform PEM -keyout ./reticleCA/private/ca.key
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
    
    #Generate the CSR.
    openssl req -config openssl.cnf -newkey rsa:2048 -nodes -sha1 \
        -keyout nodeCerts/node_$COUNTER.key -keyform PEM -out nodeCerts/node_$COUNTER.req -outform PEM
    
    #Sign the CSR.
    openssl ca -config openssl.cnf -batch -notext \
        -in nodeCerts/node_$COUNTER.req -out nodeCerts/node_$COUNTER.pem
    
    #Delete the CSR, it's done now.
    rm nodeCerts/node_$COUNTER.req
    
done


