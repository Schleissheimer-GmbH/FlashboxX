#!/bin/bash

# set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

# TODO: Change target and source address
DOIPTA=0x103F
DOIPSA=0x0E81

# TODO: Change target and source ip address
DOIPTIP=fd53:7cb8:383:2::3f
DOIPSIP=fd53:7cb8:383:2::11

# TODO: Change source ip used for network management
# See flashenv_send_nm.py
NMIPSIP=fd53:7cb8:383:2::58

# TODO: Change expected response for read idents
EXPECTED_IDENT="E121E121E121B221B315B306"

DOTESTLOOP=0
PORT="0"
ROOT_DIR=/flashboxx_env

usage() { 
  echo "Usage: $0 [-p <portname>]" 1>&2; exit 1;
}

while getopts "p:" options; do
  case "${options}" in
    p)
      PORT="${OPTARG}"
      if [[ $PORT != "0" && $PORT != "1" ]]; then
        echo "Error: Port must be 0 or 1."
        usage
      fi
      ;;
    :)
      echo "Error: -${OPTARG} requires an argument."
      usage
      ;;
    *)
      usage
      ;;
  esac
done

LED_SCRIPT="fbx-switch-led-$PORT.sh"
POWERSWITCH="fbx-switch-power$PORT.sh"
CANIFNAME="canfd$PORT"
BROADRIFNAME="broadr$PORT"
PIDFILE=/var/run/tcpdump_port${PORT}.pid
LOGDIR=/var/log/flashboxx_env
LOGFILE=${LOGDIR}/flasher_port${PORT}.log
DUMPFILE=${LOGDIR}/tcpdump_port${PORT}.pcap
ODXFILE=""

FLASHFOLDER="${ROOT_DIR}/flashfiles"

# Internal Variables
FAIL_COUNT=0
SUCCESS_COUNT=0

# shellcheck source=./flashenv_functions.sh
source "${ROOT_DIR}/flashenv_functions.sh"

function led_blink_running() {

  ${LED_SCRIPT} on cyan 500
}

function led_blink_ready() {

  ${LED_SCRIPT} on magenta 500
}

function led_blink_error() {

  ${LED_SCRIPT} on red 500
}

function wait_for_key_press() {

  log "Waiting for key press $PORT"
  while true; do
    local key=$(fbx-detect-keypress.sh)
    log "Key $key pressed"
    if [ "$key" == "$PORT" ]; then
      break
    fi
  done
}

function wait_until_device_connected() {

  log "Waiting for ECU connect"

  $POWERSWITCH On

  # wait for 3 positive responses to tester present service
  TPOK=0
  TPNOK=0
  while true; do
    sleep 1
    doip_send_uds_no_output "3E 00"
    if [[ "${OUTPUT[@]}" == "7E 00" ]]; then
      ((TPOK = TPOK + 1))
      if [[ $TPOK -gt 2 ]]; then
        log "ECU connected"
        sleep 5
        break
      fi
    else
      ((TPNOK = TPNOK + 1))
      if [[ $TPNOK -gt 10 ]]; then
        log "Error: ECU not detected"
        led_blink_error
        TPNOK=0
        $POWERSWITCH Off
        if [ ${DOTESTLOOP} -eq 0 ]; then
          wait_for_key_press
        else
          sleep 5
        fi
        led_blink_running
        $POWERSWITCH On
        sleep 5
      fi
      TPOK=0
    fi
  done
}

function wait_until_device_disconnected() {

  log "Wait for ECU disconnect"

  # wait for 3 unanswered tester present services
  TPFAIL=0
  while true; do
    sleep 1
    doip_send_uds_no_output "3E 00"
    if [[ "${OUTPUT[@]}" == "7E 00" ]]; then
      TPFAIL=0
    else
      ((TPFAIL = TPFAIL + 1))
      if [[ $TPFAIL -gt 2 ]]; then
        log "ECU disconnected"
        break
      fi
    fi
  done
}

function setup_can() {
  log "Setup $CANIFNAME"
  ip link set dev $CANIFNAME txqueuelen 4096 type can bitrate 500000 dbitrate 2000000 fd on restart-ms 500 berr-reporting on
  ip link set dev $CANIFNAME up
}

function setup_broadr() {
  log "Setup $BROADRIFNAME"

  # Deactivate flow lables
  sysctl -w net.ipv6.auto_flowlabels=0

  # Disable IPv6 autoconfiguration
  sysctl -w net.ipv6.conf.$BROADRIFNAME.autoconf=0

  # Disable router advertisements (RA)
  sysctl -w net.ipv6.conf.$BROADRIFNAME.accept_ra=0

  # Disable router forwarding
  sysctl -w net.ipv6.conf.$BROADRIFNAME.forwarding=0

  # Disable duplicate address detection
  sysctl -w net.ipv6.conf.$BROADRIFNAME.dad_transmits=0

  # Configure Interace with IP and VLAN ID
  ip link add link $BROADRIFNAME name $BROADRIFNAME.2 type vlan id 2
  ip addr add $DOIPSIP/64 dev $BROADRIFNAME.2
  ip addr add $NMIPSIP/64 dev $BROADRIFNAME.2

  # Bring Interface Up
  ip link set dev $BROADRIFNAME up
}

function start_kl15() {
  log "Start KL15 message in background"
  cangen $CANIFNAME -g 100 -I 3C0 -D 7A000200 -L 4 &
}

function read_idents() {
  # Sw component version
  IDENT=""
  doip_send_uds "22 F1 AB"
  for ((i = 3; i < ${#OUTPUT[@]}; i++)); do
    IDENT=$IDENT$(echo -e "\x${OUTPUT[$i]}")
  done
  log "Sw component version: $IDENT"
  if [[ $IDENT == ${EXPECTED_IDENT}* ]]; then
    log "SoftwareBlockVersion result:OK"
  else
    FLASHRESULT=1
    log "SoftwareBlockVersion result:ERROR"
  fi

  # EyeQ alive state
  IDENT=""
  doip_send_uds "22 F1 89"
  for ((i = 3; i < ${#OUTPUT[@]}; i++)); do
    IDENT=$IDENT$(echo -e "\x${OUTPUT[$i]}")
  done
  log "EyeQ alive state: $IDENT"

  # Magna SW version
  IDENT=""
  doip_send_uds "22 10 03"
  for ((i = 3; i < ${#OUTPUT[@]}; i++)); do
    IDENT=$IDENT$(echo -e "${OUTPUT[$i]} ")
  done
  log "Magna SW version: $IDENT"

  # EyeQ running vision?
  IDENT=""
  doip_send_uds "22 10 00"
  for ((i = 3; i < ${#OUTPUT[@]}; i++)); do
    IDENT=$IDENT$(echo -e "\x${OUTPUT[$i]}")
  done
  log "EyeQ running vision: $IDENT"

  # Get HW version
  IDENT=""
  doip_send_uds "22 F1 A3"
  for ((i = 3; i < ${#OUTPUT[@]}; i++)); do
    IDENT=$IDENT$(echo -e "\x${OUTPUT[$i]}")
  done
  log "Get HW version: $IDENT"

  # FAZIT ID
  IDENT=""
  doip_send_uds "22 F1 7C"
  for ((i = 3; i < ${#OUTPUT[@]}; i++)); do
    IDENT=$IDENT$(echo -e "\x${OUTPUT[$i]}")
  done
  log "FAZIT ID: $IDENT"

  # VW Spare Part Number
  IDENT=""
  doip_send_uds "22 F1 87"
  for ((i = 3; i < ${#OUTPUT[@]}; i++)); do
    IDENT=$IDENT$(echo -e "\x${OUTPUT[$i]}")
  done
  log "VW Spare Part Number: $IDENT"
}


function flash() {

  TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)
  LOGPREFIX=${LOGDIR}/${TIMESTAMP}_port${PORT}

  log "Start Flash $TIMESTAMP"

  log "Start tcpdump in background"
  rm -f nohup.out
  nohup tcpdump -ni $BROADRIFNAME -s 0 -w ${DUMPFILE} &
  echo $! >$PIDFILE

  sleep 1

  params=()
  params+=(--use_eth)
  params+=(--target_ip)
  params+=($DOIPTIP)
  params+=(--source_ip)
  params+=($DOIPSIP)
  params+=(--phy_target_address)
  params+=($DOIPTA)
  params+=(--datflash_path)
  params+=($FLASHFOLDER)
  params+=(--tester_present_cycletime_msec)
  params+=(0)
  params+=(--disable_comm_ctrl)
  params+=(--force_update)
  params+=(--disable_final_swcheck)
  params+=(--ECU_reset_mode)
  params+=(3)
  params+=(--p2_ext_server)
  params+=(10000)
  params+=(--source_address)
  params+=($DOIPSA)
  params+=(--disable_prog_date_serial)


  if [ -n "$ODXFILE" ]; then
    params+=(--odx_file)
    params+=($ODXFILE)
  fi

  log "Start 80126_Flasher"
  ./tools/80126_Flasher "${params[@]}" >>${LOGFILE}

  FLASHRESULT=$?

  log "Flash Result: ${FLASHRESULT}"

  if [ ${FLASHRESULT} -eq 0 ]; then
    log "Reset power and read idents"
    $POWERSWITCH Off
    sleep 1
    $POWERSWITCH On
    sleep 5
    read_idents
    sleep 1
  fi

  # Stop tcp dump process
  if [ -f $PIDFILE ]; then
    kill $(cat $PIDFILE)
    rm -f $PIDFILE
  else
    log "tcpdump not running"
  fi
}

# Create log directory
mkdir -p ${LOGDIR}


# Rename old logs from stopped flashing
TIMESTAMP=$(date +%Y-%m-%d-%H-%M-%S)
LOGPREFIX=${LOGDIR}/${TIMESTAMP}_port${PORT}

if [ -f "$LOGFILE" ] && [ -s "$LOGFILE" ]; then
  cp ${LOGFILE} ${LOGPREFIX}_flasher_STOPPED.log
fi
if [ -f "$DUMPFILE" ]; then
  mv ${LOGFILE} ${LOGPREFIX}_tcpdump_STOPPED.pcap
fi

# Clear log file
> ${LOGFILE}

log "--- Flasher ---"

if [ "$EUID" -ne 0 ]; then
  log "ERROR: you must be root do run this script"
  exit
fi

cd ${ROOT_DIR}

# Check if the directory contains exactly one file with .pdx extension
if [ "$(find "${FLASHFOLDER}" -maxdepth 1 -type f -name "*.pdx" | wc -l)" -eq 1 ]; then
    # Get the name of the file without extension
    ODXFILE=$(basename "$(find "$FLASHFOLDER" -maxdepth 1 -type f -name "*.pdx")" .pdx)
    ODXFILE="${ODXFILE}.odx-f"
    log "Force flashing odx file '$ODXFILE'"
else
    log "Start without odx_file parameter (will search fitting odx file)"
fi

setup_can
setup_broadr
start_kl15

$POWERSWITCH Off

./flashenv_send_nm.py $BROADRIFNAME.2 &

while true; do

  led_blink_ready

  if [ ${DOTESTLOOP} -eq 0 ]; then
    wait_for_key_press
  fi

  led_blink_running

  wait_until_device_connected

  flash

  $POWERSWITCH Off

  # Process flash result, rename logs to OK/ERROR
  if [ ${FLASHRESULT} -eq 0 ]; then
    ((SUCCESS_COUNT = SUCCESS_COUNT + 1))
    log "Flash result:OK success_count:${SUCCESS_COUNT} error_count:${FAIL_COUNT}"
    cp ${LOGFILE} ${LOGPREFIX}_flasher_OK.log
    if [ ${DOTESTLOOP} -eq 0 ]; then
      rm ${DUMPFILE} # remove pcap file on success
    else
      mv ${DUMPFILE} ${LOGPREFIX}_tcpdump_OK.pcap
    fi
    ${LED_SCRIPT} on green
  else
    ((FAIL_COUNT = FAIL_COUNT + 1))
    log "Flash result:ERROR success_count:${SUCCESS_COUNT} error_count:${FAIL_COUNT}"
    cp ${LOGFILE} ${LOGPREFIX}_flasher_ERROR.log
    mv ${DUMPFILE} ${LOGPREFIX}_tcpdump_ERROR.pcap
    ${LED_SCRIPT} on red
  fi

  # Clear log file
  > ${LOGFILE}

  if [ ${DOTESTLOOP} -eq 0 ]; then
    wait_for_key_press
  else
    sleep 60
  fi

done
