--------------------------------------------------------------------------------
-- 10_dashboard_load_setup.sql
-- Mini-DOWNER continuous workload support for ADB Performance Dashboard demos.
--
-- Run as DOWNER_DEMO.
-- Requires CREATE JOB, granted by 00_create_users.sql.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE ON
SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON

BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE SEQUENCE downer_dashboard_load_run_seq
      START WITH 1
      INCREMENT BY 1
      NOCACHE
  ]';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -955 THEN
      RAISE;
    END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE TABLE downer_dashboard_load_runs (
      run_id            NUMBER PRIMARY KEY,
      sql_tag           VARCHAR2(64) NOT NULL,
      anchor_mode       VARCHAR2(16) NOT NULL,
      status            VARCHAR2(16) NOT NULL,
      requested_workers NUMBER NOT NULL,
      started_at        TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
      ends_at           TIMESTAMP WITH TIME ZONE NOT NULL,
      stopped_at        TIMESTAMP WITH TIME ZONE,
      total_executions  NUMBER DEFAULT 0 NOT NULL,
      last_heartbeat    TIMESTAMP WITH TIME ZONE,
      note              VARCHAR2(4000)
    )
  ]';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -955 THEN
      RAISE;
    END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE TABLE downer_dashboard_load_workers (
      run_id            NUMBER NOT NULL,
      worker_id         NUMBER NOT NULL,
      job_name          VARCHAR2(128) NOT NULL,
      status            VARCHAR2(16) NOT NULL,
      executions        NUMBER DEFAULT 0 NOT NULL,
      last_anchor_id    VARCHAR2(64),
      last_result_count NUMBER,
      last_heartbeat    TIMESTAMP WITH TIME ZONE,
      error_message     VARCHAR2(4000),
      CONSTRAINT pk_downer_dashboard_load_workers PRIMARY KEY (run_id, worker_id)
    )
  ]';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -955 THEN
      RAISE;
    END IF;
END;
/

CREATE OR REPLACE PROCEDURE downer_dashboard_execute_once (
  p_sql_tag      IN VARCHAR2,
  p_anchor_id    IN VARCHAR2,
  p_result_count OUT NUMBER
) AS
  v_sql CLOB;
BEGIN
  v_sql := '
    SELECT /* ' || p_sql_tag || ' */
           COUNT(*)
    FROM GRAPH_TABLE (downer_graph
      MATCH (u1 IS user_account) -[e1 IS uses_device]-> (d IS device)
                                 <-[e2 IS uses_device]- (u2 IS user_account)
      WHERE u1.id = :anchor_id
        AND u1.id <> u2.id
        AND e1.end_date IS NULL
        AND e2.end_date IS NULL
      COLUMNS (
        u2.id AS neighbor_user_id,
        d.id AS shared_device_id,
        e2.device_type AS edge_device_type
      )
    )';

  EXECUTE IMMEDIATE v_sql INTO p_result_count USING p_anchor_id;
END;
/

CREATE OR REPLACE PROCEDURE stop_downer_dashboard_load AS
BEGIN
  UPDATE downer_dashboard_load_runs
  SET status = 'STOPPING',
      stopped_at = COALESCE(stopped_at, SYSTIMESTAMP),
      note = 'Stop requested by operator'
  WHERE status = 'RUNNING';

  COMMIT;

  FOR job_rec IN (
    SELECT job_name
    FROM user_scheduler_jobs
    WHERE job_name LIKE 'DDASH\_%' ESCAPE '\'
  ) LOOP
    BEGIN
      DBMS_SCHEDULER.STOP_JOB(job_name => job_rec.job_name, force => TRUE);
    EXCEPTION
      WHEN OTHERS THEN
        NULL;
    END;

    BEGIN
      DBMS_SCHEDULER.DROP_JOB(job_name => job_rec.job_name, force => TRUE);
    EXCEPTION
      WHEN OTHERS THEN
        NULL;
    END;
  END LOOP;

  UPDATE downer_dashboard_load_workers
  SET status = 'STOPPED',
      last_heartbeat = SYSTIMESTAMP
  WHERE status IN ('STARTING', 'RUNNING');

  UPDATE downer_dashboard_load_runs
  SET status = 'STOPPED',
      stopped_at = COALESCE(stopped_at, SYSTIMESTAMP)
  WHERE status = 'STOPPING';

  COMMIT;
END;
/

CREATE OR REPLACE PROCEDURE downer_dashboard_load_worker (
  p_run_id      IN NUMBER,
  p_worker_id   IN NUMBER,
  p_sql_tag     IN VARCHAR2,
  p_end_at_text IN VARCHAR2,
  p_anchor_mode IN VARCHAR2
) AS
  v_end_at       TIMESTAMP WITH TIME ZONE;
  v_status       VARCHAR2(16);
  v_anchor_mode  VARCHAR2(16) := UPPER(p_anchor_mode);
  v_anchor_id    VARCHAR2(64);
  v_result_count NUMBER;
  v_executions   NUMBER := 0;
  v_error_message VARCHAR2(4000);
BEGIN
  v_end_at := TO_TIMESTAMP_TZ(p_end_at_text, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM');

  DBMS_APPLICATION_INFO.SET_MODULE(
    module_name => 'MINI_DOWNER_DASHBOARD_LOAD',
    action_name => p_sql_tag || ':W' || p_worker_id
  );

  UPDATE downer_dashboard_load_workers
  SET status = 'RUNNING',
      last_heartbeat = SYSTIMESTAMP
  WHERE run_id = p_run_id
    AND worker_id = p_worker_id;
  COMMIT;

  LOOP
    EXIT WHEN SYSTIMESTAMP >= v_end_at;

    SELECT status
    INTO v_status
    FROM downer_dashboard_load_runs
    WHERE run_id = p_run_id;

    EXIT WHEN v_status != 'RUNNING';

    IF v_anchor_mode = 'HOT' THEN
      v_anchor_id := 'U00000042';
    ELSIF v_anchor_mode = 'RANDOM' THEN
      v_anchor_id := 'U' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1, 12001)), 8, '0');
    ELSE
      IF MOD(v_executions, 4) = 0 THEN
        v_anchor_id := 'U' || LPAD(TRUNC(DBMS_RANDOM.VALUE(1, 12001)), 8, '0');
      ELSE
        v_anchor_id := 'U00000042';
      END IF;
    END IF;

    downer_dashboard_execute_once(p_sql_tag, v_anchor_id, v_result_count);
    v_executions := v_executions + 1;

    IF MOD(v_executions, 5) = 0 THEN
      UPDATE downer_dashboard_load_workers
      SET executions = v_executions,
          last_anchor_id = v_anchor_id,
          last_result_count = v_result_count,
          last_heartbeat = SYSTIMESTAMP
      WHERE run_id = p_run_id
        AND worker_id = p_worker_id;
      COMMIT;
    END IF;
  END LOOP;

  UPDATE downer_dashboard_load_workers
  SET status = 'DONE',
      executions = v_executions,
      last_anchor_id = v_anchor_id,
      last_result_count = v_result_count,
      last_heartbeat = SYSTIMESTAMP
  WHERE run_id = p_run_id
    AND worker_id = p_worker_id;

  UPDATE downer_dashboard_load_runs
  SET total_executions = total_executions + v_executions,
      last_heartbeat = SYSTIMESTAMP,
      stopped_at = CASE
        WHEN SYSTIMESTAMP >= ends_at AND stopped_at IS NULL THEN SYSTIMESTAMP
        ELSE stopped_at
      END,
      status = CASE
        WHEN SYSTIMESTAMP >= ends_at THEN 'DONE'
        ELSE status
      END
  WHERE run_id = p_run_id;

  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    v_error_message := SUBSTR(SQLERRM, 1, 4000);

    UPDATE downer_dashboard_load_workers
    SET status = 'ERROR',
        executions = v_executions,
        last_anchor_id = v_anchor_id,
        last_heartbeat = SYSTIMESTAMP,
        error_message = v_error_message
    WHERE run_id = p_run_id
      AND worker_id = p_worker_id;

    UPDATE downer_dashboard_load_runs
    SET status = 'ERROR',
        stopped_at = SYSTIMESTAMP,
        note = SUBSTR('Worker ' || p_worker_id || ': ' || v_error_message, 1, 4000)
    WHERE run_id = p_run_id;

    COMMIT;
    RAISE;
END;
/

CREATE OR REPLACE PROCEDURE start_downer_dashboard_load (
  p_minutes     IN NUMBER DEFAULT 12,
  p_workers     IN NUMBER DEFAULT 4,
  p_sql_tag     IN VARCHAR2 DEFAULT 'DOWNER_MI_Q01_DASH_BEFORE',
  p_anchor_mode IN VARCHAR2 DEFAULT 'MIXED'
) AS
  v_run_id      NUMBER;
  v_workers     NUMBER := LEAST(GREATEST(TRUNC(p_workers), 1), 12);
  v_minutes     NUMBER := LEAST(GREATEST(p_minutes, 1), 240);
  v_sql_tag     VARCHAR2(64);
  v_anchor_mode VARCHAR2(16);
  v_ends_at     TIMESTAMP WITH TIME ZONE;
  v_ends_text   VARCHAR2(64);
  v_job_name    VARCHAR2(128);
BEGIN
  stop_downer_dashboard_load;

  v_sql_tag := REGEXP_REPLACE(UPPER(SUBSTR(p_sql_tag, 1, 60)), '[^A-Z0-9_]', '_');
  IF v_sql_tag NOT LIKE 'DOWNER_MI_Q01%' THEN
    RAISE_APPLICATION_ERROR(-20000, 'SQL tag must start with DOWNER_MI_Q01');
  END IF;

  v_anchor_mode := UPPER(SUBSTR(p_anchor_mode, 1, 16));
  IF v_anchor_mode NOT IN ('HOT', 'RANDOM', 'MIXED') THEN
    v_anchor_mode := 'MIXED';
  END IF;

  SELECT downer_dashboard_load_run_seq.NEXTVAL
  INTO v_run_id
  FROM dual;

  v_ends_at := SYSTIMESTAMP + NUMTODSINTERVAL(v_minutes, 'MINUTE');
  v_ends_text := TO_CHAR(v_ends_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM');

  INSERT INTO downer_dashboard_load_runs (
    run_id,
    sql_tag,
    anchor_mode,
    status,
    requested_workers,
    started_at,
    ends_at,
    note
  ) VALUES (
    v_run_id,
    v_sql_tag,
    v_anchor_mode,
    'RUNNING',
    v_workers,
    SYSTIMESTAMP,
    v_ends_at,
    'Dashboard load started'
  );

  FOR i IN 1 .. v_workers LOOP
    v_job_name := 'DDASH_' || v_run_id || '_' || i;

    INSERT INTO downer_dashboard_load_workers (
      run_id,
      worker_id,
      job_name,
      status,
      last_heartbeat
    ) VALUES (
      v_run_id,
      i,
      v_job_name,
      'STARTING',
      SYSTIMESTAMP
    );

    DBMS_SCHEDULER.CREATE_JOB(
      job_name => v_job_name,
      job_type => 'PLSQL_BLOCK',
      job_action => 'BEGIN downer_dashboard_load_worker(' ||
        v_run_id || ',' ||
        i || ',''' ||
        v_sql_tag || ''',''' ||
        v_ends_text || ''',''' ||
        v_anchor_mode || '''); END;',
      enabled => FALSE,
      auto_drop => TRUE
    );
  END LOOP;

  COMMIT;

  FOR job_rec IN (
    SELECT job_name
    FROM downer_dashboard_load_workers
    WHERE run_id = v_run_id
    ORDER BY worker_id
  ) LOOP
    DBMS_SCHEDULER.ENABLE(job_rec.job_name);
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Started Mini-DOWNER dashboard load run_id=' || v_run_id);
  DBMS_OUTPUT.PUT_LINE('sql_tag=' || v_sql_tag || ', workers=' || v_workers || ', minutes=' || v_minutes || ', anchor_mode=' || v_anchor_mode);
END;
/

CREATE OR REPLACE PROCEDURE show_downer_dashboard_load_status AS
BEGIN
  FOR run_rec IN (
    SELECT *
    FROM downer_dashboard_load_runs
    ORDER BY run_id DESC
    FETCH FIRST 5 ROWS ONLY
  ) LOOP
    DBMS_OUTPUT.PUT_LINE(
      'run_id=' || run_rec.run_id ||
      ', tag=' || run_rec.sql_tag ||
      ', status=' || run_rec.status ||
      ', workers=' || run_rec.requested_workers ||
      ', total_execs=' || run_rec.total_executions ||
      ', ends_at=' || TO_CHAR(run_rec.ends_at, 'YYYY-MM-DD HH24:MI:SS TZH:TZM')
    );
  END LOOP;
END;
/

GRANT SELECT ON downer_dashboard_load_runs TO graph_diag_user;
GRANT SELECT ON downer_dashboard_load_workers TO graph_diag_user;

PROMPT Dashboard load support installed.
PROMPT Use 11_start_dashboard_load_before.sql, 12_start_dashboard_load_after.sql, and 13_stop_dashboard_load.sql.
