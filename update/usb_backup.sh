#!/bin/bash

set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: you must be root to run this script"
  exit 1
fi

echo "Creating backup"
tar -cf flashboxx_backup.tar --exclude="/flashboxx_env/flashfiles/Unpacked" /flashboxx_env
tar -rf flashboxx_backup.tar /usr/local/bin

usb_path=/media/usb0
updater=fbx-auto.sh

echo "Write update script '$updater'"
echo '#!/bin/sh'                                                >  $updater
echo                                                            >> $updater
echo 'switch_leds() {'                                          >> $updater
echo '  for i in 0 1 2 3'                                       >> $updater
echo '  do'                                                     >> $updater
echo '    fbx-switch-led-$i.sh $@'                              >> $updater
echo '  done'                                                   >> $updater
echo '}'                                                        >> $updater
echo                                                            >> $updater
echo 'log() {'                                                  >> $updater
echo '  echo "$@"'                                              >> $updater
echo '  logger "$@"'                                            >> $updater
echo '}'                                                        >> $updater
echo                                                            >> $updater
echo 'copylog() {'                                              >> $updater
echo '  current_datetime=$(date +"%Y-%m-%d-%H-%M-%S")'          >> $updater
echo '  cp /var/log/syslog /media/usb0/syslog_$current_datetime'>> $updater
echo '}'                                                        >> $updater
echo                                                            >> $updater
echo 'log "Start restoring backup from usb"'                    >> $updater
echo 'switch_leds on blue 500'                                  >> $updater
echo 'log "Cleanup flash files /flashboxx_env/flashfiles"'      >> $updater
echo 'rm -r /flashboxx_env/flashfiles/* 2>/dev/null'            >> $updater
echo                                                            >> $updater
echo 'log "Extract tar archive"'                                >> $updater
echo 'tar -xf /media/usb0/flashboxx_backup.tar --overwrite -C /'>> $updater
echo                                                            >> $updater
echo 'if [ $? -ne 0 ]; then'                                    >> $updater
echo '  log "ERROR: restoring backup failed"'                   >> $updater
echo '  switch_leds on red'                                     >> $updater
echo '  copylog'                                                >> $updater
echo '  exit 1'                                                 >> $updater
echo 'fi'                                                       >> $updater
echo                                                            >> $updater
echo 'switch_leds on green'                                     >> $updater
echo 'log "All files updated, waiting for key press to reboot"' >> $updater
echo 'copylog'                                                  >> $updater
echo 'fbx-detect-keypress.sh'                                   >> $updater
echo                                                            >> $updater
echo 'switch_leds off'                                          >> $updater
echo 'reboot'                                                   >> $updater
echo 'exit 0'                                                   >> $updater

usb_info=$(lsblk -o NAME,MOUNTPOINT)
usb_line=$(echo "$usb_info" | grep "/media" | head -n 1)

if [[ -z "$usb_line" ]]; then
  echo "No usb stick detected to copy backup"
else
  echo "Copy backup to '$usb_path'"
  cp flashboxx_backup.tar $usb_path
  if [ $? -ne 0 ]; then
    echo "ERROR: Copy to usb stick failed!"
    exit 2
  fi
  cp $updater $usb_path
  sync
fi

echo "Backup finished successfully"
exit 0