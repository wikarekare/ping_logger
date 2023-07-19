#!/bin/bash
#Get Configuration definitions. Passed in as $1
. $1

LOCK_PID_FILE=${TMP_DIR}/pingtest.lock
${LOCKFILE} ${LOCK_PID_FILE} $$
if [ $? != 0 ] ; then  exit 0 ; fi

start_date=`date "+%Y-%m-%d %H:%M:00"`
echo "Start run for time ${start_date}"


#Collect the pings and log into DB
echo "fping: $(date)"
${FPING} -t 250 -p 500 -C 5 -q -f  ${FPING_HOSTS} 2>&1 | ${SBIN_DIR}/monitor/load_ping_sql.rb $1 "${start_date}"

# The snmp check only checks switches that the previous fping succeeded.
# So must be after the fping. This stops long delays, waiting for switches that aren't online.
echo "launch snmp_logger.sh"
/wikk/sbin/monitor/snmp_logger.sh $1 "${start_date}" 2&>1 > ${TMP_DIR}/snmp_logger.out &

echo "record: " $(date)
${SBIN_DIR}/monitor/graph_host_status.rb

echo "End Run: " $(date)

rm -f ${LOCK_PID_FILE}
