DROP TABLE BCH_CLEAN_PROC;

CREATE TABLE BCH_CLEAN_PROC
(
    REC_ID VARCHAR2(80) NOT NULL PRIMARY KEY,
    CUSTOMER_ID INTEGER,
    SEQNO INTEGER,
    PROC_ID INTEGER NOT NULL,
    REC_TYPE_ID INTEGER NOT NULL,
    STATUS CHAR(1) NOT NULL,
    CREATED DATE DEFAULT SYSDATE,
    UPDATED DATE
)
NOLOGGING;

CREATE INDEX BCH_CLEAN_PROC_IDX ON BCH_CLEAN_PROC (PROC_ID, REC_TYPE_ID, STATUS);
