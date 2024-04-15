#!/bin/sh

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

TEMP_DIR="/tmp/fbx-auto"
logger "fbx-auto: temp dir: ${TEMP_DIR}"

UPDATE_PACKAGE="${USB_DIR}/fbx-auto.tar.gz"
UPDATER="${TEMP_DIR}/fbx-auto-install.sh"


if [ ! -f ${UPDATE_PACKAGE} ]; then
  logger "fbx-auto: ERROR ${UPDATE_PACKAGE} does not exist"
  exit 1
fi

if [ -d ${TEMP_DIR} ]; then
  logger "fbx-auto: ${TEMP_DIR} already exists, deleting all files"
  rm -r ${TEMP_DIR}/* >/dev/null 2>&1
  if [ ! $? -eq 0 ]; then
    logger "fbx-auto: ERROR Failed remove files from ${TEMP_DIR}"
	exit 1
  fi
else
  logger "fbx-auto: Creating ${TEMP_DIR}"
  mkdir -p ${TEMP_DIR} >/dev/null 2>&1
  if [ ! $? -eq 0 ]; then
    logger "fbx-auto: ERROR Cannot create ${TEMP_DIR}"
	exit 1
  fi
fi

logger "fbx-auto: Extracting ${UPDATE_PACKAGE} to ${TEMP_DIR}"
tar -xzf ${UPDATE_PACKAGE} -C ${TEMP_DIR}

if [ $? -eq 0 ]; then
    # Run Updater from Temporary Directory
    logger "fbx-auto: Running ${UPDATER}"
    cd ${TEMP_DIR}
    (su root bash -c "${UPDATER} ${USB_DIR}" >/dev/null 2>&1) & disown
else
    logger "fbx-auto: ERROR: Unpack ${UPDATE_PACKAGE} to ${TEMP_DIR} failed"
fi

exit 0
