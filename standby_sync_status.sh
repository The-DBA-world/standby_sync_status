#!/bin/bash
# #########################################################################################
# This script MUST run from the Primary DB server.
# It checks the LAG between Primary & Standby database
# To be run by ORACLE user		
# #########################################################################################

# ######################################
# Variables MUST be modified by the user: [Otherwise the script will not work]
# ######################################

# Here you replace youremail@yourcompany.com with your Email address:
EMAIL="youremail@yourcompany.com"

# Replace ${ORACLE_SID} with the Primary DB instance SID:
ORACLE_SID=${ORACLE_SID}

# Replace STANDBY_TNS_ENTRY with the Standby Instance TNS entry you configured in the primary site tnsnames.ora file:
DRDBNAME=STANDBY_DB

# Replace ${ORACLE_HOME} with the ORACLE_HOME path on the primary server:
ORACLE_HOME=${ORACLE_HOME}

# Log Directory Location:
LOG_DIR='/tmp'

# Here you replace DBA_USER with a real user having DBA privlege:
ID=DBA_USER

# Here you replace ABC123 with the DBA user password on the standby DB:
CRD='ABC123'

# Replace "5" with the number of LAGGED ARCHIVELOGS if reached an Email alert will be sent to the receiver:
LAGTHRESHOLD=5

export EMAIL
export ORACLE_SID
export DRDBNAME
export ORACLE_HOME
export LOG_DIR
export ID
export CRD
export LAGTHRESHOLD

# #############################################
# Other variables will be picked automatically:
# #############################################

SCRIPT_NAME="check_standby_lag.sh"
export SCRIPT_NAME

SRV_NAME=`uname -n`
export SRV_NAME

LNXVER=`cat /etc/redhat-release | grep -o '[0-9]'|head -1`
export LNXVER

MAIL_LIST="-r ${SRV_NAME} ${EMAIL}"
export MAIL_LIST

# Neutralize login.sql file:
# #########################
# Existance of login.sql file under current working directory eliminates many functions during the execution of this script:

        if [ -f ./login.sql ]
         then
mv ./login.sql   ./login.sql_NeutralizedBy${SCRIPT_NAME}
        fi


# #########################################
# Script part to execute On the Primary:
# #########################################
# Check the current Redolog sequence number:
PRDBNAME_RAW=$(${ORACLE_HOME}/bin/sqlplus -S "/ as sysdba" << EOF
select name from v\$database;
exit;
EOF
)

PRDBNAME=`echo ${PRDBNAME_RAW} | awk '{print $NF}'`

PRSEQ_RAW=$(${ORACLE_HOME}/bin/sqlplus -S "/ as sysdba" << EOF
select max(a.sequence#) from v\$archived_log a, v\$database d where a.resetlogs_change# = d.resetlogs_change#;
exit;
EOF
)

PRSEQ=`echo ${PRSEQ_RAW} | awk '{print $NF}'`
export PRSEQ


# #########################################
# Script part to execute On the STANDBY:
# #########################################

# Get the last applied Archive Sequence number from the Standby DB:

DRSEQ_RAW=$(${ORACLE_HOME}/bin/sqlplus -S "/ as sysdba" << EOF
conn ${ID}/"${CRD}"@${DRDBNAME}

select max(a.sequence#) from v\$archived_log a, v\$database d where a.resetlogs_change# = d.resetlogs_change# and a.applied in ('YES','IN-MEMORY');
exit;
EOF
)

DRSEQ=`echo ${DRSEQ_RAW} | awk '{print $NF}'`
export DRSEQ

# Compare Both PRSEQ & DRSEQ to detect the lag:
# ############################################
LAG=$((${PRSEQ}-${DRSEQ}))
export LAG

	if [ ${LAG} -ge ${LAGTHRESHOLD} ]
		then
${ORACLE_HOME}/bin/sqlplus -S "/ as sysdba" << EOF

set linesize 1000 pages 100

spool ${LOG_DIR}/DR_LAST_APPLIED_SEQ.log

PROMPT Current Log Sequence on the Primary DB:
PROMPT ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
select a.thread#, max(a.sequence#) "CURRENT_SEQUENCE" from v\$archived_log a, v\$database d where a.resetlogs_change# = d.resetlogs_change# group by a.thread# order by 1;

PROMPT
PROMPT Last Applied Log Sequence# on the Standby DB:
PROMPT ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

conn ${ID}/"${CRD}"@${DRDBNAME}
set linesize 1000 pages 100

select a.THREAD#, max(a.sequence#) MAX_APPLIED_SEQUENCE from v\$archived_log a, v\$database d where a.resetlogs_change# = d.resetlogs_change# and a.applied in ('YES','IN-MEMORY') group by a.THREAD# order by 1;

set pages 0 echo off feedback off
select 'Time LAG between Primary and Standby is: ['||value||'] | [+DD HH:MI:SS]' from v\$dataguard_stats where name='apply lag';
PROMPT ***********************************

spool off
exit;
EOF
# Send Email with LAG details:
echo "Sending an Email alert ..."
mail -s "ALARM: DR DB [ ${DRDBNAME} ] is LAGGING ${LAG} sequences behind Primary DB [ ${PRDBNAME} ] on Server [ ${SRV_NAME} ]" ${MAIL_LIST} < ${LOG_DIR}/DR_LAST_APPLIED_SEQ.log
        fi

echo
echo Primary DB Sequence is: ${PRSEQ}
echo Standby DB Sequence is: ${DRSEQ}
echo Number of Lagged Archives Between Primary and Standby is: ${LAG}
echo

# De-Neutralize login.sql file:
# ############################
# If login.sql was renamed during the execution of the script revert it back to its original name:
        if [ -f ./login.sql_NeutralizedBy${SCRIPT_NAME} ]
         then
mv ./login.sql_NeutralizedBy${SCRIPT_NAME}  ./login.sql
        fi

# #############
# END OF SCRIPT
# #############
