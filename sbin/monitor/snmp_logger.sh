#!/bin/bash
# start_date is $2
# Get Configuration definitions. Passed in as $1
. $1

LOCK_PID_FILE=${TMP_DIR}/snmptest.lock
${LOCKFILE} ${LOCK_PID_FILE} $$
if [ $? != 0 ] ; then  exit 0 ; fi

start_date=$2

# Collect switch port status, and record up as pingable in the lastseen table
# Relies on fping recording that each switch is pingable.
# This stops snmp queries to unresponsive switch causing long delays.
echo "snmp switch check: " $(date)
${SBIN_DIR}/monitor/switch_port_check.rb "${start_date}"
echo "snmp finished: " $(date)

rm -f ${LOCK_PID_FILE}
