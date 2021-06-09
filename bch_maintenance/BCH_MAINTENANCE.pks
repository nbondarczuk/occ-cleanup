CREATE OR REPLACE PACKAGE CGSYSADM.BCH_MAINTENANCE
AS
    TYPE t_rowid_tab IS TABLE OF rowid;
/*
** $Name: not supported by cvs2svn $
** $Revision: 1.4 $
** $Date: 2011-07-14 11:06:27 $
*/

/*
 * Filename : BCH_MAINTENANCE.sql
 *
 * MODIFICATION HISTORY
 *
 * AUTHOR              DATE        DESCRIPTION
 * ------------------- ----------- ------------------------------------------------------
 * Andrzej Zakrzewski  02 Jan 2006 C0420 - Initial version
 * Andrzej Zakrzewski  26 Mar 2007 Renaming package from STONOGA_MAINTENANCE to BCH_MAINTENANCE
 *                                 Adding new tables maintained by package :
 *                                 CONTR_SERVICES_BCK, CUSTOMER_ALL_BCK, FEES_BCK
 * Maciej Miko³ajczuk  11 Jun 2008 2.00 Migrated to BSCS iX
 * Andrzej Zakrzewski  26 May 2010 2.01 PN3123329 - new requirements to partitioning of the stonoga/min_consumption tables
 * Norbert Bondarczuk  06 Oct 2020 HRM-4108 fees, fees_ophxact cleanup procedures
*/

CHECK_CONSTRAINT_VIOLATED EXCEPTION;
PRAGMA EXCEPTION_INIT(CHECK_CONSTRAINT_VIOLATED, -2290);

FUNCTION PrintBodyVersion RETURN VARCHAR2;

PROCEDURE housekeeping(
            in_months        IN NUMBER DEFAULT 42,
            in_mode          IN VARCHAR2 DEFAULT 'DISPLAY',
            in_partitions_no IN NUMBER DEFAULT 3);

PROCEDURE truncate_bkp_tables( in_reuse_storage IN BOOLEAN := FALSE );

PROCEDURE CleanProcPrep(pProcNo IN INTEGER,
                        pRecDelFeesOhxact OUT INTEGER,
                        pRecDelFees OUT INTEGER,
                        pMaxYears IN INTEGER DEFAULT 6,
                        pTransPackSize IN INTEGER DEFAULT 500,
                        pMaxRecNo IN INTEGER DEFAULT 1000000000);

PROCEDURE CleanProcRun(pProcId IN INTEGER,
                       pRecDelFeesOhxact OUT INTEGER,
                       pRecDelFees OUT INTEGER,
                       pOpMode IN VARCHAR2 DEFAULT 'COMMIT',
                       pTransPackSize IN INTEGER DEFAULT 500);

END BCH_MAINTENANCE;

/
CREATE OR REPLACE PUBLIC SYNONYM BCH_MAINTENANCE FOR CGSYSADM.BCH_MAINTENANCE;

GRANT EXECUTE ON CGSYSADM.BCH_MAINTENANCE TO BSCS_ROLE;
/
