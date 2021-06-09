This is a FEES/FEES_OHXACT table cleaner application.

The usage info may be obtained bu suing it with option -h, which gives:

Usage: sh_retention_fees.sh - Old fees cleanup tool
       [-h] - help, this one
       [-b] - backup rows in *_DEL tables before delete
       [-c CONNECT_STRING] - Oracle DB connect string
       [-l FINAL_LOG_DIR] - move log from /tmp to final location
       [-r MAXRECNO] - process max records in one run	   
       [-t] - test mode, rollback after all
       [-T TRANSPACKSIZE] - transaction package size	   
       [-y MAXYEARS] - set years limit for cleanup

It removes entries older than N years. The default value is 6 years but it
can be changed with an option -y.

The removal is done in batches of 500 (default) records. This can be changed
with an option -T.

It does a backup of the records being deleted if called with -b flag. The tables
used in backup have the same name as the FEES or FEES_OHXACT but _DEL suffix is
added.

The removal may be done in rollback or test mode. It can be triggered
with an option -t. Each delete will be done but rollback will be done after
the batch of removals.

The initial log from the operations is produced in /tmp location. Upon exit
it may be moved to a locatiot specified with option -l. The debugging level
may be triggered with env variable DEBUG set to 1 or in the invocation as

	DEBUG=1 sh_retention_fees.sh

The Oracle DB used may be changed ith option -c where the connection string
is specified as <user>/<password>@<dbname>.

