#!/bin/bash

/tmp/crypt/portalsmash/portalsmash.rb -n /tmp/crypt/portalsmash/networks.yaml -d wlan0 -s /tmp/crypt/working/overall.pid &
/tmp/crypt/overall.sh
