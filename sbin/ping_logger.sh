#!/bin/sh
#Get Configuration definitions. Passed in as $1
. $1

LOCK_PID_FILE=${TMP_DIR}/pingtest.lock
${LOCKFILE} ${LOCK_PID_FILE} $$
if [ $? != 0 ] ; then  exit 0 ; fi

start_date=`date "+%Y-%m-%d %H:%M:00"`

#Collect the pings and log into DB
${FPING} -t 250 -p 500 -C 5 -q -f  ${CONF_DIR}/hosts 2>&1 | ${SBIN_DIR}/monitor/load_ping_sql.rb $1 "${start_date}"

# Collect switch port status, and record up as pingable in the lastseen table
${SBIN_DIR}/monitor/switch_port_check.rb "${start_date}"

#Graph the current network status and leave the resulting png on the web server.
#${SBIN_DIR}/monitor/graph_net_status.rb | ${DOT} -Tcmapx -o ${STATUS_WWW_DIR}/bbstatusmap.html -Tpng -o ${STATUS_WWW_DIR}/bbstatus.png

#${SBIN_DIR}/graph_host_status.rb $1

rm -f ${LOCK_PID_FILE}
