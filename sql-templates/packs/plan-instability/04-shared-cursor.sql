SELECT
  child_number,
  optimizer_mismatch,
  stats_row_mismatch,
  user_bind_peek_mismatch,
  bind_uacs_diff,
  use_feedback_stats,
  literal_mismatch,
  force_hard_parse,
  DBMS_LOB.SUBSTR(reason, 300, 1) AS reason_preview
FROM v$sql_shared_cursor
WHERE sql_id = '__SQL_ID__'
ORDER BY child_number
