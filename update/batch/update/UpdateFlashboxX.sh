#!/bin/bash

# Cleanup flash files /flashboxx_env/flashfiles
rm -r /flashboxx_env/flashfiles/*

cd /tmp/update

# Copy new flash files from flashfiles folder
cp flashfiles/* /flashboxx_env/flashfiles/

# Update do flash script to use new odx file
cp flashenv_do_flash.sh /flashboxx_env/
chmod +x /flashboxx_env/flashenv_do_flash.sh

# Restart the Flashbox
shutdown -r now

exit 0
