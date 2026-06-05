--------------------------------------------------------------------------------
-- 31_fixed_rate_load_setup.sql
-- Fixed-rate Mini-DOWNER workload for visual Performance Hub impact demos.
--
-- Run as DOWNER_DEMO after 10_dashboard_load_setup.sql.
-- This path intentionally executes the graph SQL without before/after comments.
--------------------------------------------------------------------------------

WHENEVER SQLERROR EXIT SQL.SQLCODE

SET DEFINE ON
SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON

BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE SEQUENCE downer_fixed_rate_run_seq
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
    CREATE TABLE downer_fixed_rate_runs (
      run_id                    NUMBER PRIMARY KEY,
      workload_name             VARCHAR2(64) NOT NULL,
      anchor_mode               VARCHAR2(16) NOT NULL,
      status                    VARCHAR2(16) NOT NULL,
      requested_workers         NUMBER NOT NULL,
      target_execs_per_minute   NUMBER NOT NULL,
      started_at                TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP NOT NULL,
      ends_at                   TIMESTAMP WITH TIME ZONE NOT NULL,
      stopped_at                TIMESTAMP WITH TIME ZONE,
      total_executions          NUMBER DEFAULT 0 NOT NULL,
      total_elapsed_ms          NUMBER DEFAULT 0 NOT NULL,
      last_heartbeat            TIMESTAMP WITH TIME ZONE,
      note                      VARCHAR2(4000)
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
    CREATE TABLE downer_fixed_rate_workers (
      run_id                    NUMBER NOT NULL,
      worker_id                 NUMBER NOT NULL,
      job_name                  VARCHAR2(128) NOT NULL,
      status                    VARCHAR2(16) NOT NULL,
      target_execs_per_minute   NUMBER NOT NULL,
      executions                NUMBER DEFAULT 0 NOT NULL,
      total_elapsed_ms          NUMBER DEFAULT 0 NOT NULL,
      last_elapsed_ms           NUMBER,
      last_anchor_id            VARCHAR2(64),
      last_result_count         NUMBER,
      last_heartbeat            TIMESTAMP WITH TIME ZONE,
      error_message             VARCHAR2(4000),
      CONSTRAINT pk_downer_fixed_rate_workers PRIMARY KEY (run_id, worker_id)
    )
  ]';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -955 THEN
      RAISE;
    END IF;
END;
/

CREATE OR REPLACE FUNCTION downer_elapsed_ms (
  p_started_at IN TIMESTAMP WITH TIME ZONE,
  p_ended_at   IN TIMESTAMP WITH TIME ZONE
) RETURN NUMBER AS
  v_delta INTERVAL DAY TO SECOND;
BEGIN
  v_delta := p_ended_at - p_started_at;
  RETURN ROUND(
      EXTRACT(DAY FROM v_delta) * 86400000
    + EXTRACT(HOUR FROM v_delta) * 3600000
    + EXTRACT(MINUTE FROM v_delta) * 60000
    + EXTRACT(SECOND FROM v_delta) * 1000,
    3
  );
END;
/

CREATE OR REPLACE PROCEDURE downer_fixed_rate_sleep (
  p_seconds IN NUMBER
) AS
  v_seconds NUMBER := LEAST(GREATEST(NVL(p_seconds, 0), 0), 60);
BEGIN
  IF v_seconds <= 0 THEN
    RETURN;
  END IF;

  BEGIN
    EXECUTE IMMEDIATE 'BEGIN DBMS_SESSION.SLEEP(:seconds); END;' USING v_seconds;
    RETURN;
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  BEGIN
    EXECUTE IMMEDIATE 'BEGIN DBMS_LOCK.SLEEP(:seconds); END;' USING v_seconds;
    RETURN;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(-20001, 'No sleep API is available for fixed-rate workload pacing');
  END;
END;
/

CREATE OR REPLACE PROCEDURE downer_fixed_rate_execute_once (
  p_anchor_id    IN VARCHAR2,
  p_result_count OUT NUMBER
) AS
  v_sql CLOB;
BEGIN
  v_sql := q'[
      SELECT COUNT(*)
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
      )]';

  EXECUTE IMMEDIATE v_sql INTO p_result_count USING p_anchor_id;
END;
/

CREATE OR REPLACE PROCEDURE stop_downer_fixed_rate_load AS
BEGIN
  UPDATE downer_fixed_rate_runs
  SET status = 'STOPPING',
      stopped_at = COALESCE(stopped_at, SYSTIMESTAMP),
      note = 'Stop requested by operator'
  WHERE status = 'RUNNING';

  COMMIT;

  FOR job_rec IN (
    SELECT job_name
    FROM user_scheduler_jobs
    WHERE job_name LIKE 'DFIX\_%' ESCAPE '\'
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

  UPDATE downer_fixed_rate_workers
  SET status = 'STOPPED',
      last_heartbeat = SYSTIMESTAMP
  WHERE status IN ('STARTING', 'RUNNING');

  UPDATE downer_fixed_rate_runs
  SET status = 'STOPPED',
      stopped_at = COALESCE(stopped_at, SYSTIMESTAMP)
  WHERE status = 'STOPPING';

  COMMIT;
END;
/

CREATE OR REPLACE PROCEDURE downer_fixed_rate_worker (
  p_run_id           IN NUMBER,
  p_worker_id        IN NUMBER,
  p_end_at_text      IN VARCHAR2,
  p_anchor_mode      IN VARCHAR2,
  p_interval_seconds IN NUMBER
) AS
  v_end_at             TIMESTAMP WITH TIME ZONE;
  v_status             VARCHAR2(16);
  v_anchor_mode        VARCHAR2(16) := UPPER(p_anchor_mode);
  v_anchor_id          VARCHAR2(64);
  v_result_count       NUMBER;
  v_executions         NUMBER := 0;
  v_total_elapsed_ms   NUMBER := 0;
  v_elapsed_ms         NUMBER;
  v_started_at         TIMESTAMP WITH TIME ZONE;
  v_sleep_seconds      NUMBER;
  v_interval_seconds   NUMBER := GREATEST(NVL(p_interval_seconds, 1), 0.01);
  v_error_message      VARCHAR2(4000);
BEGIN
  v_end_at := TO_TIMESTAMP_TZ(p_end_at_text, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM');

  DBMS_APPLICATION_INFO.SET_MODULE(
    module_name => 'MINI_DOWNER_FIXED_RATE_LOAD',
    action_name => 'WORKER_' || p_worker_id
  );

  UPDATE downer_fixed_rate_workers
  SET status = 'RUNNING',
      last_heartbeat = SYSTIMESTAMP
  WHERE run_id = p_run_id
    AND worker_id = p_worker_id;
  COMMIT;

  LOOP
    EXIT WHEN SYSTIMESTAMP >= v_end_at;

    SELECT status
    INTO v_status
    FROM downer_fixed_rate_runs
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

    v_started_at := SYSTIMESTAMP;
    downer_fixed_rate_execute_once(v_anchor_id, v_result_count);
    v_elapsed_ms := downer_elapsed_ms(v_started_at, SYSTIMESTAMP);

    v_executions := v_executions + 1;
    v_total_elapsed_ms := v_total_elapsed_ms + v_elapsed_ms;

    IF MOD(v_executions, 10) = 0 THEN
      UPDATE downer_fixed_rate_workers
      SET executions = v_executions,
          total_elapsed_ms = v_total_elapsed_ms,
          last_elapsed_ms = v_elapsed_ms,
          last_anchor_id = v_anchor_id,
          last_result_count = v_result_count,
          last_heartbeat = SYSTIMESTAMP
      WHERE run_id = p_run_id
        AND worker_id = p_worker_id;
      COMMIT;
    END IF;

    v_sleep_seconds := v_interval_seconds - (v_elapsed_ms / 1000);
    IF v_sleep_seconds > 0 THEN
      downer_fixed_rate_sleep(v_sleep_seconds);
    END IF;
  END LOOP;

  UPDATE downer_fixed_rate_workers
  SET status = 'DONE',
      executions = v_executions,
      total_elapsed_ms = v_total_elapsed_ms,
      last_elapsed_ms = v_elapsed_ms,
      last_anchor_id = v_anchor_id,
      last_result_count = v_result_count,
      last_heartbeat = SYSTIMESTAMP
  WHERE run_id = p_run_id
    AND worker_id = p_worker_id;

  UPDATE downer_fixed_rate_runs
  SET total_executions = total_executions + v_executions,
      total_elapsed_ms = total_elapsed_ms + v_total_elapsed_ms,
      last_heartbeat = SYSTIMESTAMP,
      stopped_at = CASE
        WHEN SYSTIMESTAMP >= ends_at AND stopped_at IS NULL THEN SYSTIMESTAMP
        ELSE stopped_at
      END,
      status = CASE
        WHEN SYSTIMESTAMP >= ends_at AND status = 'RUNNING' THEN 'DONE'
        ELSE status
      END
  WHERE run_id = p_run_id;

  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    v_error_message := SUBSTR(SQLERRM, 1, 4000);

    UPDATE downer_fixed_rate_workers
    SET status = 'ERROR',
        executions = v_executions,
        total_elapsed_ms = v_total_elapsed_ms,
        last_elapsed_ms = v_elapsed_ms,
        last_anchor_id = v_anchor_id,
        last_heartbeat = SYSTIMESTAMP,
        error_message = v_error_message
    WHERE run_id = p_run_id
      AND worker_id = p_worker_id;

    UPDATE downer_fixed_rate_runs
    SET status = 'ERROR',
        stopped_at = SYSTIMESTAMP,
        note = SUBSTR('Worker ' || p_worker_id || ': ' || v_error_message, 1, 4000)
    WHERE run_id = p_run_id;

    COMMIT;
    RAISE;
END;
/

CREATE OR REPLACE PROCEDURE start_downer_fixed_rate_missing_index_load (
  p_minutes                  IN NUMBER DEFAULT 20,
  p_workers                  IN NUMBER DEFAULT 4,
  p_total_execs_per_minute   IN NUMBER DEFAULT 1200,
  p_anchor_mode              IN VARCHAR2 DEFAULT 'MIXED',
  p_stop_existing            IN VARCHAR2 DEFAULT 'Y'
) AS
  v_run_id                 NUMBER;
  v_workers                NUMBER := LEAST(GREATEST(TRUNC(p_workers), 1), 12);
  v_minutes                NUMBER := LEAST(GREATEST(p_minutes, 1), 7200);
  v_total_epm              NUMBER := LEAST(GREATEST(TRUNC(p_total_execs_per_minute), v_workers), 60000);
  v_worker_epm             NUMBER;
  v_interval_seconds       NUMBER;
  v_interval_seconds_text  VARCHAR2(64);
  v_anchor_mode            VARCHAR2(16);
  v_ends_at                TIMESTAMP WITH TIME ZONE;
  v_ends_text              VARCHAR2(64);
  v_job_name               VARCHAR2(128);
BEGIN
  IF UPPER(SUBSTR(p_stop_existing, 1, 1)) = 'Y' THEN
    stop_downer_fixed_rate_load;

    BEGIN
      EXECUTE IMMEDIATE 'BEGIN stop_downer_dashboard_load; END;';
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Dashboard-load stop skipped: ' || SQLERRM);
    END;
  END IF;

  v_anchor_mode := UPPER(SUBSTR(p_anchor_mode, 1, 16));
  IF v_anchor_mode NOT IN ('HOT', 'RANDOM', 'MIXED') THEN
    v_anchor_mode := 'MIXED';
  END IF;

  v_worker_epm := v_total_epm / v_workers;
  v_interval_seconds := 60 / v_worker_epm;
  v_interval_seconds_text := TO_CHAR(
    v_interval_seconds,
    'FM9999990D999999',
    'NLS_NUMERIC_CHARACTERS=.,'
  );

  SELECT downer_fixed_rate_run_seq.NEXTVAL
  INTO v_run_id
  FROM dual;

  v_ends_at := SYSTIMESTAMP + NUMTODSINTERVAL(v_minutes, 'MINUTE');
  v_ends_text := TO_CHAR(v_ends_at, 'YYYY-MM-DD"T"HH24:MI:SSTZH:TZM');

  INSERT INTO downer_fixed_rate_runs (
    run_id,
    workload_name,
    anchor_mode,
    status,
    requested_workers,
    target_execs_per_minute,
    started_at,
    ends_at,
    note
  ) VALUES (
    v_run_id,
    'SHARED_DEVICE_GRAPH_TRAVERSAL',
    v_anchor_mode,
    'RUNNING',
    v_workers,
    v_total_epm,
    SYSTIMESTAMP,
    v_ends_at,
    'Fixed-rate graph traversal load started'
  );

  FOR i IN 1 .. v_workers LOOP
    v_job_name := 'DFIX_' || v_run_id || '_' || i;

    INSERT INTO downer_fixed_rate_workers (
      run_id,
      worker_id,
      job_name,
      status,
      target_execs_per_minute,
      last_heartbeat
    ) VALUES (
      v_run_id,
      i,
      v_job_name,
      'STARTING',
      v_worker_epm,
      SYSTIMESTAMP
    );

    DBMS_SCHEDULER.CREATE_JOB(
      job_name => v_job_name,
      job_type => 'PLSQL_BLOCK',
      job_action => 'BEGIN downer_fixed_rate_worker(' ||
        v_run_id || ',' ||
        i || ',''' ||
        v_ends_text || ''',''' ||
        v_anchor_mode || ''',' ||
        v_interval_seconds_text || '); END;',
      enabled => FALSE,
      auto_drop => TRUE
    );
  END LOOP;

  COMMIT;

  FOR job_rec IN (
    SELECT job_name
    FROM downer_fixed_rate_workers
    WHERE run_id = v_run_id
    ORDER BY worker_id
  ) LOOP
    DBMS_SCHEDULER.ENABLE(job_rec.job_name);
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Started fixed-rate graph traversal run_id=' || v_run_id);
  DBMS_OUTPUT.PUT_LINE('workers=' || v_workers || ', minutes=' || v_minutes || ', target_epm=' || v_total_epm || ', anchor_mode=' || v_anchor_mode || ', stop_existing=' || UPPER(SUBSTR(p_stop_existing, 1, 1)));
END;
/

CREATE OR REPLACE PROCEDURE show_downer_fixed_rate_status AS
BEGIN
  FOR run_rec IN (
    SELECT *
    FROM downer_fixed_rate_runs
    ORDER BY run_id DESC
    FETCH FIRST 5 ROWS ONLY
  ) LOOP
    DBMS_OUTPUT.PUT_LINE(
      'run_id=' || run_rec.run_id ||
      ', workload=' || run_rec.workload_name ||
      ', status=' || run_rec.status ||
      ', workers=' || run_rec.requested_workers ||
      ', target_epm=' || run_rec.target_execs_per_minute ||
      ', total_execs=' || run_rec.total_executions ||
      ', avg_elapsed_ms=' ||
        CASE
          WHEN run_rec.total_executions > 0 THEN TO_CHAR(ROUND(run_rec.total_elapsed_ms / run_rec.total_executions, 3))
          ELSE 'n/a'
        END ||
      ', ends_at=' || TO_CHAR(run_rec.ends_at, 'YYYY-MM-DD HH24:MI:SS TZH:TZM')
    );
  END LOOP;
END;
/

GRANT SELECT ON downer_fixed_rate_runs TO graph_diag_user;
GRANT SELECT ON downer_fixed_rate_workers TO graph_diag_user;

PROMPT Fixed-rate load support installed.
PROMPT Use 32_start_fixed_rate_missing_index_window.sql to start a fixed-rate window.
PROMPT Use 33_stop_fixed_rate_load.sql to stop it and 34_show_fixed_rate_load_status.sql to inspect it.
