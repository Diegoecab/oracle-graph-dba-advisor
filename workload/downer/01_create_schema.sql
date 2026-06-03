--------------------------------------------------------------------------------
-- 01_create_schema.sql
-- Mini-DOWNER schema creation.
--
-- Run as DOWNER_DEMO.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON

BEGIN
  EXECUTE IMMEDIATE 'DROP PROPERTY GRAPH DOWNER_GRAPH';
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
/

BEGIN
  FOR t IN (
    SELECT table_name
    FROM user_tables
    WHERE table_name IN (
      'E_USES_IP',
      'E_USES_CARD',
      'E_WITHDRAWAL_BANK_ACCOUNT',
      'E_USES_DEVICE',
      'N_IP',
      'N_CARD',
      'N_BANK_ACCOUNT',
      'N_DEVICE',
      'N_USER'
    )
    ORDER BY CASE WHEN table_name LIKE 'E_%' THEN 1 ELSE 2 END
  ) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/

CREATE TABLE n_user (
  id                     VARCHAR2(64) NOT NULL,
  start_date             TIMESTAMP DEFAULT SYSTIMESTAMP,
  last_updated           TIMESTAMP DEFAULT SYSTIMESTAMP,
  registration_date      TIMESTAMP,
  is_test_user           NUMBER(1,0),
  card_types_own         VARCHAR2(64),
  card_types_contagion   VARCHAR2(64),
  adjacent_edges_count   NUMBER(10,0),
  cancelled_date         TIMESTAMP,
  CONSTRAINT n_user_pk PRIMARY KEY (id)
);

CREATE TABLE n_device (
  id                     VARCHAR2(64) NOT NULL,
  start_date             TIMESTAMP DEFAULT SYSTIMESTAMP,
  last_updated           TIMESTAMP DEFAULT SYSTIMESTAMP,
  device_type            VARCHAR2(64),
  adjacent_edges_count   NUMBER(10,0),
  CONSTRAINT n_device_pk PRIMARY KEY (id)
);

CREATE TABLE n_bank_account (
  id                     VARCHAR2(64) NOT NULL,
  start_date             TIMESTAMP DEFAULT SYSTIMESTAMP,
  last_updated           TIMESTAMP DEFAULT SYSTIMESTAMP,
  adjacent_edges_count   NUMBER(10,0),
  CONSTRAINT n_bank_account_pk PRIMARY KEY (id)
);

CREATE TABLE n_card (
  id                     VARCHAR2(64) NOT NULL,
  start_date             TIMESTAMP DEFAULT SYSTIMESTAMP,
  last_updated           TIMESTAMP DEFAULT SYSTIMESTAMP,
  adjacent_edges_count   NUMBER(10,0),
  CONSTRAINT n_card_pk PRIMARY KEY (id)
);

CREATE TABLE n_ip (
  id                     VARCHAR2(64) NOT NULL,
  start_date             TIMESTAMP DEFAULT SYSTIMESTAMP,
  last_updated           TIMESTAMP DEFAULT SYSTIMESTAMP,
  adjacent_edges_count   NUMBER(10,0),
  CONSTRAINT n_ip_pk PRIMARY KEY (id)
);

CREATE TABLE e_uses_device (
  id             VARCHAR2(256) NOT NULL,
  src            VARCHAR2(64) NOT NULL,
  dst            VARCHAR2(64) NOT NULL,
  start_date     TIMESTAMP DEFAULT SYSTIMESTAMP,
  last_updated   TIMESTAMP DEFAULT SYSTIMESTAMP,
  device_type    VARCHAR2(64),
  end_date       TIMESTAMP,
  CONSTRAINT e_uses_device_pk PRIMARY KEY (id),
  CONSTRAINT e_uses_device_src_fk FOREIGN KEY (src) REFERENCES n_user(id),
  CONSTRAINT e_uses_device_dst_fk FOREIGN KEY (dst) REFERENCES n_device(id)
);

CREATE TABLE e_withdrawal_bank_account (
  id             VARCHAR2(256) NOT NULL,
  src            VARCHAR2(64) NOT NULL,
  dst            VARCHAR2(64) NOT NULL,
  start_date     TIMESTAMP DEFAULT SYSTIMESTAMP,
  last_updated   TIMESTAMP DEFAULT SYSTIMESTAMP,
  end_date       TIMESTAMP,
  CONSTRAINT e_withdrawal_bank_account_pk PRIMARY KEY (id),
  CONSTRAINT e_wba_src_fk FOREIGN KEY (src) REFERENCES n_user(id),
  CONSTRAINT e_wba_dst_fk FOREIGN KEY (dst) REFERENCES n_bank_account(id)
);

CREATE TABLE e_uses_card (
  id             VARCHAR2(256) NOT NULL,
  src            VARCHAR2(64) NOT NULL,
  dst            VARCHAR2(64) NOT NULL,
  start_date     TIMESTAMP DEFAULT SYSTIMESTAMP,
  last_updated   TIMESTAMP DEFAULT SYSTIMESTAMP,
  end_date       TIMESTAMP,
  CONSTRAINT e_uses_card_pk PRIMARY KEY (id),
  CONSTRAINT e_uses_card_src_fk FOREIGN KEY (src) REFERENCES n_user(id),
  CONSTRAINT e_uses_card_dst_fk FOREIGN KEY (dst) REFERENCES n_card(id)
);

CREATE TABLE e_uses_ip (
  id             VARCHAR2(256) NOT NULL,
  src            VARCHAR2(64) NOT NULL,
  dst            VARCHAR2(64) NOT NULL,
  start_date     TIMESTAMP DEFAULT SYSTIMESTAMP,
  last_updated   TIMESTAMP DEFAULT SYSTIMESTAMP,
  used_at_date   TIMESTAMP,
  end_date       TIMESTAMP,
  CONSTRAINT e_uses_ip_pk PRIMARY KEY (id),
  CONSTRAINT e_uses_ip_src_fk FOREIGN KEY (src) REFERENCES n_user(id),
  CONSTRAINT e_uses_ip_dst_fk FOREIGN KEY (dst) REFERENCES n_ip(id)
);

CREATE INDEX idx_e_wba_src_end_dst ON e_withdrawal_bank_account (src, end_date, dst);
CREATE INDEX idx_e_wba_dst_end_src ON e_withdrawal_bank_account (dst, end_date, src);
CREATE INDEX idx_e_uses_card_src_end_dst ON e_uses_card (src, end_date, dst);
CREATE INDEX idx_e_uses_card_dst_end_src ON e_uses_card (dst, end_date, src);
CREATE INDEX idx_e_uses_ip_src_end_dst ON e_uses_ip (src, end_date, dst);
CREATE INDEX idx_e_uses_ip_dst_end_src ON e_uses_ip (dst, end_date, src);

PROMPT Mini-DOWNER schema created. E_USES_DEVICE intentionally has no SRC/DST leading indexes.
