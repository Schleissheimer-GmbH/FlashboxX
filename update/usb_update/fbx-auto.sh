#!/bin/sh


switch_leds() {

  for i in 0 1 2 3
  do
    fbx-switch-led-$i.sh $@
  done 
}

USERNAME="$(id -u -n)"
USERID="$(id -u)"

# See all the logger messages /var/log/messages
logger "fbx-auto: Starting fbx-auto.sh as ${USERNAME} id ${USERID}"
logger "fbx-auto: USB Device Info: ${UM_DEVICE} ${UM_FILESYSTEM} ${UM_VENDOR} ${UM_MODEL}"

if [ -z "${UM_MOUNTPOINT}" ]
then
  USB_DIR="/media/usb0"
  logger "fbx-auto: default mount point ${USB_DIR}"
else
  USB_DIR=${UM_MOUNTPOINT}
  logger "fbx-auto: mount point ${USB_DIR}"
fi

logger "Cleanup flash files /flashboxx_env/flashfiles"
rm -r /flashboxx_env/flashfiles/*

logger "Copy new flash files from flashfiles folder"
cp $USB_DIR/flashfiles/* /flashboxx_env/flashfiles/

logger "Update do flash script to use new odx file"
cp $USB_DIR/flashenv_do_flash.sh /flashboxx_env/
chmod +x /flashboxx_env/flashenv_do_flash.sh

switch_leds on green

logger "All files updated, wait for key press"

fbx-detect-keypress.sh

switch_leds off

shutdown -r now
exit 0
