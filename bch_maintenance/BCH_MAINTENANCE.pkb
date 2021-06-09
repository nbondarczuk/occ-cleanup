CREATE OR REPLACE PACKAGE BODY CGSYSADM.BCH_MAINTENANCE
AS

/*
** $Name: not supported by cvs2svn $
** $Revision: 1.5 $
** $Date: 2011-07-28 13:29:54 $
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
 * Leszek Góryñski     17 Jun 2008 2.01 Removed excessive owner name
 * Andrzej Zakrzewski  26 May 2010 2.02 PN3123329 - new requirements to partitioning of the stonoga/min_consumption tables
 *
*/

/* name of the last partition */
LAST_PARTITION_NAME CONSTANT VARCHAR2(20) := 'ALL_THE_REST';


FUNCTION PrintBodyVersion RETURN VARCHAR2
IS
BEGIN
    RETURN '$Name: not supported by cvs2svn $ | $Header: /var/home/lgo/MIG_SRC_LG_20120914/plsql/bch_maintenance/BCH_MAINTENANCE.pkb,v 1.5 2011-07-28 13:29:54 aza Exp $';
END;

/*
 * Procedure name : SHOW_INFO
 * Descritpion    : Displays information about operations performed by package
 *                        the output is generated only if variable DBMSOUT is TRUE
 *                                        The output can be visible if SERVEROUTPUT option is enabled
 *
 * Returns        : none
 */

PROCEDURE show_info( in_text IN VARCHAR2 )
AS
BEGIN
  dbms_output.put_line(in_text);
END show_info;


/*
 * Procedure name : EXECUTE_SQL
 * Descritpion    : Executes dynamically SQL
 *
 * Returns        : none
 */
PROCEDURE execute_sql(
            in_sql              IN VARCHAR2,
            in_mode             IN VARCHAR2)
AS
BEGIN
  IF in_mode NOT IN ('EXEC', 'DISPLAY') THEN
    raise_application_error(-20001, 'EXECUTE_SQL: wrong mode: ' || in_mode);
  END IF;

  IF in_mode = 'EXEC' THEN
    EXECUTE IMMEDIATE in_sql;
  END IF;

  show_info(in_sql);

END execute_sql;


/*
 * Procedure name : SPLIT_PARTITION
 * Descritpion    : Split existing parition on two seperate partitions
 *                  using partitioning key passed to procedure.
 *                  The new partitions are put into tablespace set through parameter.
 *
 * Returns        : none
 */
PROCEDURE split_partition(
            in_table_name       IN VARCHAR2,
            in_split_partition  IN VARCHAR2,
            in_split_value      IN VARCHAR2,
            in_split_part_name1 IN VARCHAR2,
            in_split_part_name2 IN VARCHAR2,
            in_tablespace_name  IN VARCHAR2,
            in_mode             IN VARCHAR2)
AS
  lv_stmt VARCHAR2(32000);

BEGIN
  lv_stmt := 'ALTER TABLE '||in_table_name||' '||
             'SPLIT PARTITION '||in_split_partition||' at ('||in_split_value||') '||
             'INTO '||
             '( PARTITION '||in_split_part_name1||' TABLESPACE '||in_tablespace_name||', '||
             '  PARTITION '||in_split_part_name2||' TABLESPACE '||in_tablespace_name||' ) '||
             'UPDATE GLOBAL INDEXES';

  execute_sql(lv_stmt, in_mode);

END split_partition;


/*
 * Procedure name : REBUILD_INDEXES
 * Descritpion    : Rebuild invalid indexes
 *
 * Returns        : none
 */
PROCEDURE rebuild_indexes(
            in_table_name           IN VARCHAR2,
            in_mode                 IN VARCHAR2)
AS
  lv_stmt VARCHAR2(4000);

BEGIN
  FOR c_ind IN (SELECT DISTINCT uip.index_name, uip.partition_name
                FROM   user_indexes ui,
                       user_ind_partitions uip
                WHERE  ui.table_name = in_table_name
                  AND  ui.index_name = uip.index_name
                  AND  uip.status != 'USABLE')
  LOOP
    lv_stmt := 'ALTER INDEX ' || c_ind.index_name || ' REBUILD PARTITION ' || c_ind.partition_name;

    execute_sql(lv_stmt, in_mode);

    IF in_mode = 'EXEC' THEN
      show_info('REBUILD_INDEXES: Index '||c_ind.index_name||' partition '||c_ind.partition_name||' rebuild.');
    END IF;
  END LOOP c_ind;
END rebuild_indexes;


/*
 * Procedure name : COPY_STATISTICS
 * Descritpion    : Copy statistics between partitions
 *
 * Returns        : none
 */
PROCEDURE copy_statistics(
            in_table_name           IN VARCHAR2,
            in_last_partition_name  IN VARCHAR2,
            in_new_partition_name   IN VARCHAR2,
            in_mode                 IN VARCHAR2)
AS
  lv_stmt varchar2(4000);
BEGIN
  lv_stmt :=  'BEGIN DBMS_STATS.copy_table_stats(';
  lv_stmt := lv_stmt || ''''|| sys_context('USERENV', 'SESSION_USER')|| ''',';
  lv_stmt := lv_stmt || ''''|| in_table_name||''',';
  lv_stmt := lv_stmt || ''''|| in_last_partition_name||''',';
  lv_stmt := lv_stmt || ''''|| in_new_partition_name||'''';
  lv_stmt := lv_stmt || '); END;';

  execute_sql(lv_stmt, in_mode);
END copy_statistics;


/*
 * Procedure name : REFRESH_STATISTICS
 * Descritpion    : Generate partition statistics
 *
 * Returns        : none
 */
PROCEDURE refresh_statistics(
            in_table_name     IN VARCHAR2,
            in_partition_name IN VARCHAR2,
            in_mode           IN VARCHAR2)
AS
  lv_stmt varchar2(4000);

BEGIN
  lv_stmt := 'BEGIN DBMS_STATS.gather_table_stats (ownname => '''||sys_context('USERENV', 'SESSION_USER')||''',';
  lv_stmt := lv_stmt ||  'tabname     => '''||in_table_name||''',';
  lv_stmt := lv_stmt ||  'partname    => '''||in_partition_name||''',';
  lv_stmt := lv_stmt ||  'method_opt  => ''FOR TABLE FOR ALL COLUMNS FOR ALL INDEXES'',';
  lv_stmt := lv_stmt ||  'granularity => ''ALL'',';
  lv_stmt := lv_stmt ||  'estimate_percent => 15,';
  lv_stmt := lv_stmt ||  'cascade     => TRUE';
  lv_stmt := lv_stmt ||  '); END;';

  execute_sql(lv_stmt, in_mode);
END refresh_statistics;


/*
 * Procedure name : ADD_PARTITIONS
 * Descritpion    : Adds new partitions to table. The length of the partitions is defined
 *                  by parameter INI_SPLIT_LENGTH - it specify number of months.
 *                  Procedure adds partitions in advance starting from date set
 *                  by IND_PARTITION_DATE - by default SYSDATE is used.
 *                  Procedure adds number of partitions set by INI_PARTITIONS_NO parameters
 *                  If the partition with specific partitioning key is already created
 *                  then the new partition is not created and processing goes on
 *
 * Returns        : none
 */

PROCEDURE add_partitions (
              in_table_name     IN VARCHAR2,
              in_partitions_no  IN NUMBER,
              in_mode           IN VARCHAR2)
AS
    lb_first       BOOLEAN := FALSE;
    lb_second       BOOLEAN := FALSE;
    li_last_key_value   PLS_INTEGER;
    li_split_key_value   PLS_INTEGER;
    lv_split_part_name1 all_tab_partitions.partition_name%TYPE;
    lv_last_partition_name all_tab_partitions.partition_name%TYPE;
    lv_split_value     VARCHAR2(100);
    ld_partition_date   DATE;

    lv_tablespace_name all_tab_partitions.tablespace_name%TYPE;

    TYPE part_def_type IS RECORD
    (
      high_value all_tab_partitions.high_value%TYPE,
      partition_name all_tab_partitions.partition_name%TYPE
    );

    TYPE part_list_type IS TABLE OF part_def_type INDEX BY BINARY_INTEGER;
    ltbl_parts part_list_type;

    TYPE part_names_list_type IS TABLE OF VARCHAR2(100) INDEX BY VARCHAR2(500);
    ltbl_part_names part_names_list_type;

BEGIN
  IF NVL(in_partitions_no, 0) < 1 THEN
    RETURN;
  END IF;

  li_last_key_value := TO_NUMBER(TO_CHAR(SYSDATE, 'YYYYMM'));

  -- get last partition and previous split value
  FOR parts IN ( SELECT partition_name,
                        high_value,
                        tablespace_name,
                        partition_position
                 FROM   user_tab_partitions
                 WHERE  table_name = UPPER(in_table_name)
                 ORDER BY partition_position DESC )
  LOOP
    IF NOT lb_first THEN

      lv_tablespace_name := parts.tablespace_name;

    ELSIF lb_first AND NOT lb_second THEN

      --get last partition key as number in format YYYYMM
      BEGIN
        li_last_key_value := TO_NUMBER(SUBSTR(parts.partition_name, 3, 4)||SUBSTR(parts.partition_name, -2, 2));
        lv_last_partition_name := parts.partition_name;

        EXCEPTION
          WHEN OTHERS THEN
            NULL;
      END;

      lb_second := TRUE;
    END IF;

    lb_first := TRUE;

    ltbl_parts(parts.partition_position).high_value := parts.high_value;
    ltbl_parts(parts.partition_position).partition_name := parts.partition_name;
    ltbl_part_names(parts.partition_name) := parts.high_value;

  END LOOP;

  IF ltbl_parts.COUNT > 0  THEN

    -- add partitions in advance
    FOR part_index IN 1 .. in_partitions_no LOOP

      ld_partition_date := ADD_MONTHS(TRUNC(SYSDATE, 'MONTH'), (part_index - 1));

      li_split_key_value := TO_NUMBER(TO_CHAR(ld_partition_date, 'YYYYMM'));
      lv_split_value := 'TO_DATE('''||TO_CHAR(ADD_MONTHS(ld_partition_date, 1), 'YYYYMMDD')||''', ''YYYYMMDD'')';
      lv_split_part_name1 := 'P_'||TO_CHAR(ld_partition_date, 'YYYY')||'_'||TO_CHAR(ld_partition_date, 'MM');

      IF NOT ltbl_part_names.EXISTS(lv_split_part_name1) THEN

        --the P_LAST partition is not splited when there are other partitions with higher bounds
        IF li_last_key_value > li_split_key_value THEN
          show_info('ADD_PARTITIONS: Partition '||lv_split_part_name1 || ' for table '||in_table_name||' is bypassed because partitioning key less than highest bound');
        ELSE
          split_partition(in_table_name  => in_table_name,
                          in_split_partition => LAST_PARTITION_NAME,
                          in_split_value => lv_split_value,
                          in_split_part_name1 => lv_split_part_name1,
                          in_split_part_name2 => LAST_PARTITION_NAME,
                          in_tablespace_name => lv_tablespace_name,
                          in_mode => in_mode);

          IF lv_last_partition_name IS NOT NULL THEN
            copy_statistics(in_table_name => in_table_name,
                            in_last_partition_name => lv_last_partition_name,
                            in_new_partition_name => lv_split_part_name1,
                            in_mode => in_mode);
          END IF;

          IF in_mode = 'EXEC' THEN
            show_info('ADD_PARTITIONS: Partition '||lv_split_part_name1 || ' is added with key '||lv_split_value);
          END IF;
        END IF;

      END IF;

    END LOOP;

  ELSE
      raise_application_error(-20001, 'The table '||UPPER(in_table_name)||' doesn''t have last partition');
  END IF;


END add_partitions;


/*
 * DEL_PARTITION
 */
PROCEDURE del_partition(
            in_table_name     IN VARCHAR2,
            in_partition_name IN VARCHAR2,
            in_mode           IN VARCHAR2)
AS
  lv_stmt VARCHAR2(100);

BEGIN
  lv_stmt := 'ALTER TABLE ' || in_table_name ||
             ' DROP PARTITION ' || in_partition_name ||
             ' UPDATE GLOBAL INDEXES';

  execute_sql(lv_stmt, in_mode);

  IF in_mode = 'EXEC' THEN
    show_info('DEL_PARTITION: Partition ' || in_table_name || '.' || in_partition_name || ' deleted');
  END IF;

END del_partition;


/*
 * DEL_PARTITIONS
 */
PROCEDURE del_partitions(
            in_table_name IN VARCHAR2,
            in_months     IN NUMBER,
            in_mode       IN VARCHAR2)
AS
BEGIN
  FOR part_crec IN (SELECT partition_name
                    FROM   user_tab_partitions
                    WHERE  table_name = in_table_name
                      AND  partition_name NOT IN ('ALL_THE_REST')
                    ORDER BY partition_position)
  LOOP
    IF TO_DATE(SUBSTR(part_crec.partition_name, 3, 7)||'_01', 'YYYY_MM_DD') < ADD_MONTHS(SYSDATE, in_months * -1) THEN
      del_partition(in_table_name, part_crec.partition_name, in_mode);
    END IF;
  END LOOP;

END del_partitions;


PROCEDURE housekeeping(
            in_months        IN NUMBER DEFAULT 42,
            in_mode          IN VARCHAR2 DEFAULT 'DISPLAY',
            in_partitions_no IN NUMBER DEFAULT 3)
AS
  CURSOR part_tables_cur
  IS
  SELECT DISTINCT table_name
  FROM   user_tab_partitions
  WHERE  table_name LIKE 'STONOGA_%' OR table_name LIKE 'MIN_CONS%';

BEGIN
  show_info('HOUSEKEEPING STARTED');
  show_info('HOUSEKEEPING PARAMETERS'||' IN_MONTHS: '||in_months||' IN_MODE: '||in_mode);

  IF in_mode NOT IN ('EXEC', 'DISPLAY') THEN
    raise_application_error(-20001, 'HOUSEKEEPING: wrong mode: ' || in_mode);
  END IF;

  IF in_months < 0 THEN
    raise_application_error(-20001, 'HOUSEKEEPING: wrong IN_MONTHS: ' || in_months);
  END IF;

  /*
   * DELETE OLD PARTITIONS - we keep them default 24 months
   */
  FOR table_crec IN part_tables_cur
  LOOP
    del_partitions(table_crec.table_name, in_months, in_mode);
  END LOOP;


  /*
   * CREATE NEW PARTITIONS FOR THIS MONTH
   */
  FOR table_crec IN part_tables_cur
  LOOP
    add_partitions(table_crec.table_name, in_partitions_no, in_mode);
  END LOOP;


  /*
   * REBUILD ONLINE INDEXES
   */
  FOR table_crec IN part_tables_cur
  LOOP
    rebuild_indexes(table_crec.table_name, in_mode);
  END LOOP;

  show_info('HOUSEKEEPING TERMINATED');

END housekeeping;


/*
 * Procedure name : TRUNCATE_BKP_TABLES
 * Descritpion    : Procedure truncates temporary tables purged in case of integration tests
 *                  In case of integration tests you can invoke it to fasten data clearance
 *
 * Returns        : none
 */
PROCEDURE truncate_bkp_tables ( in_reuse_storage IN BOOLEAN := FALSE )
AS
  lv_reuse_storage_clause VARCHAR2(50);

BEGIN
  IF in_reuse_storage = TRUE THEN
    lv_reuse_storage_clause := ' REUSE STORAGE';
  END IF;

  execute_sql('TRUNCATE TABLE MIN_CONSUMPTION_BKP'||lv_reuse_storage_clause, 'EXEC');
  execute_sql('TRUNCATE TABLE MIN_CONSUMPTION_DETAILS_BKP'||lv_reuse_storage_clause, 'EXEC');
  execute_sql('TRUNCATE TABLE STONOGA_FEES_BKP'||lv_reuse_storage_clause, 'EXEC');
  execute_sql('TRUNCATE TABLE MC_BONUS_BKP_BILLSEQNO'||lv_reuse_storage_clause, 'EXEC');
  execute_sql('TRUNCATE TABLE FEES_SB_DETAILS_BKP'||lv_reuse_storage_clause, 'EXEC');
  execute_sql('TRUNCATE TABLE FEES_SB_BKP'||lv_reuse_storage_clause, 'EXEC');

END truncate_bkp_tables;

/*
 * Procedure name : CleanProcPrepFees
 * Descritpion    : Procedure prepares deletion of old records
 * Returns        : none
 */
PROCEDURE CleanProcPrepFees(pProcNo IN INTEGER,
                            pRecsDel OUT INTEGER,
                            pMaxYears IN INTEGER DEFAULT 6,
                            pMaxRecNo IN INTEGER DEFAULT 1000000000)
AS
BEGIN
    insert into bch_clean_proc
    (
            PROC_ID,
            REC_TYPE_ID,
            STATUS,
            REC_ID,
            CUSTOMER_ID,
            SEQNO
    )
    select MOD(rownum - 1, pProcNo) + 1, 1, 'P', rowidtochar(rowid), customer_id, seqno
    from
        fees f
    where rownum <= pMaxRecNo
      and
        (
            (
                f.ohxact is NULL
            and trunc(f.valid_from) < add_months(trunc(sysdate), (-1) * pMaxYears * 12)
            )
            or
            (
                f.ohxact is not NULL
            and (f.customer_id, f.ohxact) IN
                (
                    select
                        o.customer_id,
                        o.ohxact
                        from
                        orderhdr_all o
                    where
                        trunc(nvl(o.ohrefdate, o.ohentdate)) < add_months(trunc(sysdate), (-1) * pMaxYears * 12)
                )
            )
        );

    pRecsDel := SQL%ROWCOUNT;

    commit;
END;

/*
 * Procedure name : CleanProcPrepFees
 * Descritpion    : Procedure preapres deletion of old records
 * Returns        : none
 */
PROCEDURE CleanProcPrep(pProcNo IN INTEGER,
                        pRecDelFeesOhxact OUT INTEGER,
                        pRecDelFees OUT INTEGER,
                        pMaxYears IN INTEGER DEFAULT 6,
                        pTransPackSize IN INTEGER DEFAULT 500,
                        pMaxRecNo IN INTEGER DEFAULT 1000000000)
AS
BEGIN
    EXECUTE IMMEDIATE 'TRUNCATE TABLE BCH_CLEAN_PROC';
    CleanProcPrepFees(pProcNo, pRecDelFees, pMaxYears, pMaxRecNo);
END;

/*
 * Procedure name : CleanProcRunFeesBulk
 * Descritpion    : Procedure deletes old records from FEES table
 * Returns        : number of records deleted
 */
PROCEDURE CleanProcRunFeesBulk(pProcId IN INTEGER,
                               pRecsDel OUT INTEGER,
                               pOpMode IN VARCHAR2 DEFAULT 'COMMIT',
                               pTransPackSize IN INTEGER DEFAULT 500)
AS
    cp INTEGER := 1;
    recs_del INTEGER := 0;
    i INTEGER;
    rowid_tab t_rowid_tab := t_rowid_tab();
    proc_rowid_tab t_rowid_tab := t_rowid_tab();
    vLastRowid VARCHAR2(80);
    vStatus CHAR(1);
BEGIN
    rowid_tab.EXTEND(pTransPackSize);
    proc_rowid_tab.EXTEND(pTransPackSize);
    for r in
    (
        select chartorowid(rec_id) rid, rowid prid
          from bch_clean_proc
         where proc_id = pProcId
           and rec_type_id = 1
           and status = 'P'
    )
    loop
        -- collect rowid i a collection
        rowid_tab(cp) := r.rid;
        proc_rowid_tab(cp) := r.prid;
        cp := cp + 1;

        vLastRowid := rowidtochar(r.rid);

        -- flush the cache of rowid collected
        if cp > pTransPackSize then
           -- may fail in test mode
           vStatus := 'D';
           begin
                forall i in rowid_tab.first .. rowid_tab.last
                       delete from fees
                        where rowid = rowid_tab(i);
           exception
                when CHECK_CONSTRAINT_VIOLATED
                then
                    if pOpMode = 'COMMIT'
                    then
                        --TRACE.Error('While processing last rowid: ' || vLastRowid);
                        rollback;
                        raise;
                    else
                        vStatus := 'E';
                    end if;
           end;

           recs_del := recs_del + SQL%ROWCOUNT;

           EXECUTE IMMEDIATE pOpMode;

           forall i in rowid_tab.first .. rowid_tab.last
                update bch_clean_proc
                   set status = vStatus,
                       updated = SYSDATE
                 where rowid = proc_rowid_tab(i);

           COMMIT;

           rowid_tab.DELETE;
           rowid_tab.EXTEND(pTransPackSize);
           proc_rowid_tab.DELETE;
           proc_rowid_tab.EXTEND(pTransPackSize);

           cp := 1;
        end if;
    end loop;

    -- delete any records left
    forall i in rowid_tab.first .. rowid_tab.last
        delete from fees
         where rowid = rowid_tab(i);

    recs_del := recs_del + SQL%ROWCOUNT;

    EXECUTE IMMEDIATE pOpMode;

    forall i in rowid_tab.first .. rowid_tab.last
         update bch_clean_proc
            set status = 'D',
                updated = SYSDATE
          where rowid = proc_rowid_tab(i);

    COMMIT;

    pRecsDel := recs_del;

exception
    when others then
        --TRACE.Error('While processing last rowid: ' || vLastRowid);
        rollback;
        raise;
END;

/*
 * Procedure name : CleanProcRunFeesOhxactBulk
 * Descritpion    : Procedure deletes old records from FEES_OHXACT table
 * Returns        : number of records deleted
 */
PROCEDURE CleanProcRunFeesOhxactBulk(pProcId IN INTEGER,
                                     pRecsDel OUT INTEGER,
                                     pOpMode IN VARCHAR2 DEFAULT 'COMMIT',
                                     pTransPackSize IN INTEGER DEFAULT 500)
AS
    cp INTEGER := 1;
    recs_del INTEGER := 0;
    i INTEGER;
    rowid_tab t_rowid_tab := t_rowid_tab();
    proc_rowid_tab t_rowid_tab := t_rowid_tab();
    vLastRowid VARCHAR2(80);
BEGIN
    rowid_tab.EXTEND(pTransPackSize);
    proc_rowid_tab.EXTEND(pTransPackSize);
    for r in
    (
        select chartorowid(rec_id) rid, rowid prid
          from bch_clean_proc
         where proc_id = pProcId
           and rec_type_id = 2
           and status = 'P'
    )
    loop
        -- collect rowid i a collection
        rowid_tab(cp) := r.rid;
        proc_rowid_tab(cp) := r.prid;
        cp := cp + 1;

        vLastRowid := rowidtochar(r.rid);

        -- flush the cache of rowid collected
        if cp > pTransPackSize then
           forall i in rowid_tab.first .. rowid_tab.last
                  delete from fees_ohxact
                   where rowid = rowid_tab(i);

           recs_del := recs_del + SQL%ROWCOUNT;

           EXECUTE IMMEDIATE pOpMode;

           forall i in rowid_tab.first .. rowid_tab.last
                update bch_clean_proc
                   set status = 'D',
                       updated = SYSDATE
                 where rowid = proc_rowid_tab(i);

           COMMIT;

           rowid_tab.DELETE;
           rowid_tab.EXTEND(pTransPackSize);
           proc_rowid_tab.DELETE;
           proc_rowid_tab.EXTEND(pTransPackSize);

           cp := 1;
        end if;
    end loop;

    -- delete any records left in the host array
    forall i in rowid_tab.first .. rowid_tab.last
        delete from fees_ohxact
         where rowid = rowid_tab(i);

    recs_del := recs_del + SQL%ROWCOUNT;

    EXECUTE IMMEDIATE pOpMode;

    forall i in rowid_tab.first .. rowid_tab.last
         update bch_clean_proc
            set status = 'D',
                updated = SYSDATE
          where rowid = proc_rowid_tab(i);

    COMMIT;

    pRecsDel := recs_del;

exception
    when others then
        --TRACE.Error('While processing last rowid: ' || vLastRowid);
        rollback;
        raise;
END;

/*
 * Procedure name : CleanProcRunFeesOhxactDepRecLoad
 * Descritpion    : Procedure loads dependent records from FEES_OHXACT if they were not loaded before
 * Returns        : n/a
 */
PROCEDURE CleanProcRunFeesDepRec(pProcId IN INTEGER)
IS
BEGIN
    insert into bch_clean_proc
    (
        PROC_ID,
        REC_TYPE_ID,
        STATUS,
        REC_ID,
        CUSTOMER_ID,
        SEQNO
    )
    select
        pProcId,
        2,
        'P',
        rowidtochar(fo.rowid),
        fo.customer_id,
        fo.seqno
    from fees_ohxact fo
    where (fo.customer_id, fo.seqno) in
    (
        select customer_id, seqno
        from bch_clean_proc
        where rec_type_id = 1
        and status = 'P'
        and proc_id = pProcId
    )
    and not exists
    (
        select 1
        from bch_clean_proc
        where REC_ID = rowidtochar(fo.rowid)
    );

    COMMIT;
END;

/*
 * Procedure name : CleanProcRun
 * Descritpion    : Procedure deletes old records from FEES and FEES_OHXACT table
 * Returns        : number of records deleted for each table
 */
PROCEDURE CleanProcRun(pProcId IN INTEGER,
                       pRecDelFeesOhxact OUT INTEGER,
                       pRecDelFees OUT INTEGER,
                       pOpMode IN VARCHAR2 DEFAULT 'COMMIT',
                       pTransPackSize IN INTEGER DEFAULT 500)
AS
BEGIN
    CleanProcRunFeesDepRec(pProcId);
    CleanProcRunFeesOhxactBulk(pProcId, pRecDelFeesOhxact, pOpMode, pTransPackSize);
    CleanProcRunFeesBulk(pProcId, pRecDelFees, pOpMode, pTransPackSize);
END;

END BCH_MAINTENANCE;
/
