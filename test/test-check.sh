#!/bin/bash

#
# Specific runtime Oracle SYSADM environment setup
#
export CONNECT_STRING=${CONNECT_STRING:-"CGSYSADM/cgsysadm17@T17BSCS"}

function count () {
	local SQL=$1
	local RESULT=$(sqlplus -s /NOLOG<<EOF
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
	WHENEVER SQLERROR EXIT SQL.SQLCODE;
	$SQL
	/
EOF
	)

	local ERROR_CODE=$?
	if [ ${ERROR_CODE} -gt 0 ]
	then
		return 1
	fi;

	echo $RESULT		
	
	return 0
}

function count_fees_ohxact () {
	local n=$(count "SELECT COUNT(*) FROM CGSYSADM.FEES_OHXACT_TEST")
	echo $n
	return $?
}

function count_fees () {
	local n=$(count "SELECT COUNT(*) FROM SYSADM.FEES")
	echo $n
	return $?
}

echo -n "CGSYSADM.FEES_OHXACT: "
count_fees_ohxact
if [ $? -ne 0 ]
then
	echo "Error counting CGSYSADM.FEES_OHXACT test table"
	exit 1
fi

echo -n "CGSYSADM.FEES: "
count_fees
if [ $? -ne 0 ]
then
	echo "Error counting CGSYSADM.FEES test table"
	exit 2
fi

#
# Success
#
exit 0
