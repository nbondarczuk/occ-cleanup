#!/bin/bash

################################################################################
#
# sh_retention_fees.sh
#
# Purpose: Script cleaning old FEES, FEES_OHXACT entries
#
################################################################################

#
# DEBUG = 1: write debug messages in stderr
# DEBUG = 2: debug bash hard printing execution steps in stdout
#
[[ ${DEBUG:-0} -ge 2 ]] && set -xo

################################################################################
#
# Environment: the options can be overriden by command line
#
################################################################################

#
# Specific runtime Oracle environment setup, CGSYSADM for test, SYSADM for prod
#

export CONNECT_STRING=${CONNECT_STRING:-"CGSYSADM/cgsysadm17@T17BSCS"}

#
# Processing options
#

MAXYEARS="6"
MAXRECNO="1000000000"
OPMODE="COMMIT"
TRANPACKSIZE="500"
MAXPROCNO=0
PROCID=0
FLAGS=""
VERBOSE=0

################################################################################
#
# Log handling
#
################################################################################

#
# Set default process name for logging
#

PROCESS_NAME="SH_RETENTION_FEES"

#
# Error codes
#

SUCCESS=0
ERROR_DB_CONNECT=1
ERROR_INV_OPTION=2
ERROR_PROC_COUNT=3
ERROR_PROC_CLEAN=4
ERROR_INTERRUPTED=5

#
# Log file handling
#

TMP_LOG_DIR=/tmp
LOG_STARTED=
LOG_FILE_NAME=
FINAL_LOG_DIR=

#
# Remove leading and trailing spaces
#
function trim () {
	local var="$*"
	local tvar="${var//[[:space:]]/}"
	echo -n "$tvar"
}

#
# Mask password with * sign in Oracle connect string for safe printout
#
function mask_password () {
	local IFS="/@"
	set -- $1
	password=${2//?/*}
	echo -n "$1/${password}@$3"
}

#
# Remove \n to make it printable in one line
#
function flatline () {
	local line="$*"
	echo -n ${line//\n}
}

#
# Mark start of processing defining event handlers
#
function process_start () {
	trap 'process_finish $ERROR_INTERRUPTED "\n!!! Interrupted !!!\n"' TERM HUP INT
	trap '[[ -n $FINAL_LOG_DIR ]] && mv -f ${LOG_FILE_NAME} ${FINAL_LOG_DIR}' EXIT
	local TM=$(date +"%F-%T")
	LOG_STARTED=${TM}
	PID=$$
	LOG_FILE_NAME=${TMP_LOG_DIR}/${PROCESS_NAME}-${PID}-${LOG_STARTED}.log
	local MSG="${TM} $$ INFO: Started ${PROCESS_NAME} - args: $@"
	echo -e "${MSG}" || tee -a ${LOG_FILE_NAME}
}

#
# Mark end of processing
#
function process_finish () {
	local RC="$1"
	if [ $RC -eq $SUCCESS ]
	then
		CODE="INFO"
	else
		CODE="ERROR"
	fi
	local TM=$(date +"%F-%T")
	local MSG="${TM} $$ $CODE: Finished ${PROCESS_NAME} - status: $@"
	echo -e "${MSG}" || tee -a ${LOG_FILE_NAME}
	#
	exit "$RC"
}

#
# Handle unconditional message
#
function info () {
	local MSG="$*"
	local TM=$(date +"%F-%T")
	# always write to output
	echo -e "${TM} $$ INFO: ${MSG}" | tee -a ${LOG_FILE_NAME}
}

#
# Handle unconditional message with warning
#
function warn () {
	local MSG="$*"
	local TM=$(date +"%F-%T")
	# always write to output
	echo -e "${TM} $$ WARN: ${MSG}" | tee -a ${LOG_FILE_NAME}
}

#
# Handle debug message, use it only if env variable DEBUG set
#
function debug () {
	# write to stderr output if needed
	if [ ${DEBUG:-0} -ge 1 ]
	then
		local LINE="$1"
		shift
		local MSG="$*"
		local TM=$(date +"%F-%T")
		echo -e "${TM} $$ DEBUG/$LINE: ${MSG}" | tee -a ${LOG_FILE_NAME}
	fi
}

#
# Handle error by printout to output and registering alert
#
function error () {
	local CODE="$1"
	shift
	local MSG="$*"
	local TM=$(date +"%F-%T")
	# write to output and store in DB if no debug mode
	echo -e "${TM} $$ ERROR: ${MSG}" | tee -a ${LOG_FILE_NAME}
	# exiting after all
	exit "${CODE}"
}

################################################################################
#
# Specific functions
#
################################################################################

function testDbConnect () {
	local SQL="SELECT SYSDATE FROM DUAL;"
	debug $LINENO "SQL: $SQL"
	RESULT=$(sqlplus -s /NOLOG<<EOF
	WHENEVER SQLERROR EXIT SQL.SQLCODE;
	CONNECT $CONNECT_STRING
	SET SERVEROUTPUT ON
	SET NEWPAGE
	SET SPACE 0
	SET LINESIZE 250
	SET PAGESIZE 0
	SET ECHO OFF
	SET FEEDBACK OFF
	SET HEADING OFF
	SET MARKUP HTML OFF
	SET TRIMSPOOL ON
	SET LONG 99999
	SET TERMOUT ON
	$SQL
	/
EOF
	)

	local ERROR_CODE=$?
	if [ ${ERROR_CODE} -gt 0 ]
	then
		warn "Got Oracle error: " $(flatline $RESULT)
		return 1
	fi;

	debug $LINENO "Connection validated"

	return 0
}

#
# Run pl/sql command in sqlplus, return result in the defined variable RESULT
#
function run () {
	local SQL="$1"
	debug $LINENO "SQL: $SQL"
	RESULT=$(sqlplus -s /NOLOG<<EOF
	WHENEVER SQLERROR EXIT SQL.SQLCODE;
	CONNECT $CONNECT_STRING
	SET SERVEROUTPUT ON
	SET NEWPAGE
	SET SPACE 0
	SET LINESIZE 250
	SET PAGESIZE 0
	SET ECHO OFF
	SET FEEDBACK OFF
	SET HEADING OFF
	SET MARKUP HTML OFF
	SET TRIMSPOOL ON
	SET LONG 99999
	SET TERMOUT ON
	$SQL
	/
EOF
	)

	local ERROR_CODE=$?
	if [ ${ERROR_CODE} -gt 0 ]
	then
		warn "Got Oracle error: " $(flatline $RESULT)
		return 1
	fi;

	debug $LINENO "Result: $RESULT"
	debug $LINENO "Done: $OPMODE"

	RESULT=$(trim "$RESULT")

	return 0
}

#
# Run sql command returning a scalar value in the defined variable RESULT
#
function get () {
	local SQL="$1"
	debug $LINENO "SQL: $SQL"
	RESULT=$(sqlplus -s /NOLOG<<EOF
	WHENEVER SQLERROR EXIT SQL.SQLCODE;
	CONNECT $CONNECT_STRING
	SET NEWPAGE
	SET SPACE 0
	SET LINESIZE 250
	SET PAGESIZE 0
	SET ECHO OFF
	SET FEEDBACK OFF
	SET HEADING OFF
	SET MARKUP HTML OFF
	SET TRIMSPOOL ON
	SET LONG 99999
	SET TERMOUT ON
	$SQL
	/
EOF
	)

	local ERROR_CODE=$?
	if [ ${ERROR_CODE} -gt 0 ]
	then
		warn "Got Oracle error: " $(flatline $RESULT)
		return 1
	fi;

	debug $LINENO "Result: $RESULT"

	RESULT=$(trim "$RESULT")

	return 0
}

function count_fees_ohxact () {
	debug $LINENO "Counting table: FEES_OHXACT"
	get "SELECT COUNT(*) FROM FEES_OHXACT" || return 1
	info "Count FEES_OHXACT: $RESULT rows ($1 cleanup)"
	debug $LINENO "Getting statistics from: FEES_OHXACT"
	get "SELECT TO_CHAR(MIN(BILL_DATE), 'YYYYMMDD') FROM FEES_OHXACT" || return 1
	info "Min(BILL_DATE) on FEES_OHXACT: $RESULT ($1 cleanup)"
	#
	return 0
}

function count_fees () {
	debug $LINENO "Counting table: FEES"
	get "SELECT COUNT(*) FROM FEES" || return 1
	info "Count FEES: $RESULT rows ($1 cleanup)"
	debug $LINENO "Getting statistics from: FEES"
	get "SELECT TO_CHAR(MIN(VALID_FROM), 'YYYYMMDD') FROM FEES" || return 1
	info "Min(VALID_FROM) on FEES: $RESULT ($1 cleanup)"
	#
	return 0
}

function clean_proc () {
	info "Starting process: ${PROCID}"	
	run "${SQL3}" || return 1
	info "Finished process: ${PROCID}"		
	#
	return 0
}

function clean_proc_prep () {
	info "Starting to prepare processes: ${MAXPROCNO}"
	run "${SQL2}" || return 1
	info "Prepared processes: ${MAXPROCNO}"
	#
	return 0
}

#
# Usage info
#
function usage () {
	cmd=$(basename $0)
	echo "Usage: $cmd - Old fees, fees_ohxact cleanup tool"
	echo "       [-h] - help, this one"
	echo "       [-c CONNECT_STRING] - Oracle DB connect string"
	echo "       [-l FINAL_LOG_DIR] - move log from $TMP_LOG_DIR to final location"
	echo "       [-r MAXRECNO] - process max records in one run"
	echo "       [-t] - test mode, rollback after all"
	echo "       [-T TRANSPACKSIZE] - transaction package size"
	echo "       [-y MAXYEARS] - set years limit for cleanup"
	echo "       [-P MAXPROCNO] - number of processes to start in parallel mode"
	echo "       [-p PROCID] - process id 1..MAXPROCNO if started in parallel mode"
	echo "       [-v] - verbose mode, stat in the log"
	#
	exit 0
}

################################################################################
#
# main: Processing starts here
#
################################################################################

#
# Parse invocation options fixing the SQL variable placeholders
#
while getopts "hc:l:r:ty:T:P:p:v" opt
do
	case ${opt} in
		h ) usage "$@"
			;;		
		l ) FINAL_LOG_DIR=$OPTARG
			FLAGS="$FLAGS -l $OPTARG"
			;;
		c ) CONNECT_STRING=$OPTARG
			FLAGS="$FLAGS -c $OPTARG"			
			;;
		r ) MAXRECNO=$OPTARG
			FLAGS="$FLAGS -r $OPTARG"			
			;;
		t ) OPMODE="ROLLBACK"
			FLAGS="$FLAGS -t"			
			;;
		T ) TRANPACKSIZE=$OPTARG
			FLAGS="$FLAGS -T $OPTARG"			
			;;
		y ) MAXYEARS=$OPTARG
			FLAGS="$FLAGS -y $OPTARG"			
			;;
		P ) MAXPROCNO=$OPTARG
			;;
		p ) PROCID=$OPTARG
			;;
		v ) VERBOSE=1
			;;
		\? ) echo "Invalid option: $opt"
			 exit ${ERROR_INV_OPTION}
			 ;;
	esac
done

#
# PL/SQL code statement deleting old records from FEES and FEES_OHXACT
#

SQL2="declare
	recs_del_fees_ohxact NUMBER := 0;
	recs_del_fees NUMBER := 0;
begin
	CGSYSADM.BCH_MAINTENANCE.CleanProcPrep($MAXPROCNO, recs_del_fees_ohxact, recs_del_fees, $MAXYEARS, $TRANPACKSIZE, $MAXRECNO);
	dbms_output.put_line(recs_del_fees_ohxact || ', ' || recs_del_fees);
end;
"

SQL3="declare
	recs_del_fees_ohxact NUMBER := 0;
	recs_del_fees NUMBER := 0;
begin
	CGSYSADM.BCH_MAINTENANCE.CleanProcRun($PROCID, recs_del_fees_ohxact, recs_del_fees, '$OPMODE', $TRANPACKSIZE);
	dbms_output.put_line(recs_del_fees_ohxact || ', ' || recs_del_fees);
end;
"

#
# main: Start work
#

process_start "$@"

#
# Info about processing options
#

info "Using the following options"
info "CONNECT_STRING:" $(mask_password ${CONNECT_STRING})
info "      MAXYEARS: ${MAXYEARS}"
info "      MAXRECNO: ${MAXRECNO}"
info "  TRANPACKSIZE: ${TRANPACKSIZE}"
info "        OPMODE: ${OPMODE}"
info "   TMP_LOG_DIR: ${TMP_LOG_DIR}"
info " FINAL_LOG_DIR: ${FINAL_LOG_DIR}"
info "     MAXPROCNO: ${MAXPROCNO}"
info "        PROCID: ${PROCID}"
info "       VERBOSE: ${VERBOSE}"

#
# Start fees cleanup, first on dependent tables than from the main one
#

if [ ${VERBOSE} -eq 1 -a ${PROCID} -eq 0 ]
then   
	testDbConnect || process_finish ${ERROR_DB_CONNECT} "Error connecting Oracle db with: $CONNECT_STRING"
fi

#
# Clean table FEES and FEES_OHXACT using BCH_MAINTENENCE
#

if [ ${VERBOSE} -eq 1 -a ${PROCID} -eq 0 ]
then   
   count_fees_ohxact 'before' || process_finish ${ERROR_PROC_COUNT} 'Error counting FEES_OHXACT'
   count_fees 'before' || process_finish ${ERROR_PROC_COUNT} 'Error counting FEES'
fi

if [ $MAXPROCNO -eq 0 ]
then
	# monoprocess mode, good for benchmarking	
	clean || process_finish ${ERROR_PROC_CLEAN} 'Error cleaning FEES_OHXACT'
else
	# parallel mode
	if [ $PROCID -eq 0 ]
	then
		# distribute work and start workers in the backgound
		clean_proc_prep
		for i in `seq 1 ${MAXPROCNO}`
		do
			# fork a subprocess
			sh_retention_fees.sh -P ${MAXPROCNO} -p $i ${FLAGS}&
			rc=$?
			spid=$!
			info "Forked process: " $spid $rc
		done
		# must wait for all started sub-processes
		for i in `seq 1 ${MAXPROCNO}`
		do
			wait
			rc=$?
			if [ $rc -ne 0 ]
			then
				warn "Sub-process failure detected: " $rc
			else
				info "Success in wait"
			fi
		done		
	else
		# started as single worker to handle one of 1 .. MAXPROCNO procid
		clean_proc
	fi;
fi;

if [ ${VERBOSE} -eq 1 -a ${PROCID} -eq 0 ]
then   
	count_fees_ohxact 'after' || process_finish ${ERROR_PROC_COUNT} 'Error counting FEES_OHXACT'
	count_fees 'after' || process_finish ${ERROR_PROC_COUNT} 'Error counting FEES'
fi

#
# Finish work with success
#

process_finish $SUCCESS

################################################################################
#
# main: Processing ends here
#
################################################################################
