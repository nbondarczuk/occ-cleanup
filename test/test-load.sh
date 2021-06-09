#!/bin/bash

#
# Specific runtime Oracle SYSADM environment setup
#
export CONNECT_STRING=${CONNECT_STRING:-"CGSYSADM/cgsysadm17@T17BSCS"}

function run () {
	local SQL=$1
	local RESULT=$(sqlplus -s /NOLOG<<EOF
	WHENEVER SQLERROR EXIT SQL.SQLCODE;
	CONNECT $CONNECT_STRING
	$SQL
	/
EOF
	)

	local ERROR_CODE=$?
	if [ ${ERROR_CODE} -gt 0 ]
	then
		echo $RESULT		
		return 1
	fi;

	return 0
}



function load_fees_ohxact () {
	run "TRUNCATE TABLE CGSYSADM.FEES_OHXACT_TEST"
	run "INSERT INTO CGSYSADM.FEES_OHXACT_TEST SELECT * FROM SYSADM.FEES_OHXACT"
	return $?
}

function load_fees () {
	run "TRUNCATE TABLE CGSYSADM.FEES_TEST"
	run "INSERT INTO CGSYSADM.FEES_TEST SELECT * FROM SYSADM.FEES"	
	return $?
}

run "alter table fees_ohxact DISABLE constraint FK_FEESOHXACT_FEES_TEST"

echo "Loading: CGSYSADM.FEES_TEST"
load_fees
if [ $? -ne 0 ]
then
	echo "Error loading CGSYSADM.FEES_TEST test table"
	exit 2
else
	echo "Loaded: CGSYSADM.FEES_TEST"	
fi

echo "Loading: CGSYSADM.FEES_OHXACT_TEST"
load_fees_ohxact
if [ $? -ne 0 ]
then
	echo "Error loading CGSYSADM.FEES_OHXACT_TEST test table"
	exit 1
else
	echo "Loaded: CGSYSADM.FEES_OHXACT_TEST"	
fi

run "alter table fees_ohxact enable constraint FK_FEESOHXACT_FEES_TEST"

#
# Success
#
exit 0
