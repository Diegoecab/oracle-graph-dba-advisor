SELECT *
FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
  sql_id => '__SQL_ID__',
  cursor_child_no => (
    SELECT child_number
    FROM (
      SELECT child_number
      FROM v$sql
      WHERE sql_id = '__SQL_ID__'
      ORDER BY last_active_time DESC NULLS LAST, child_number DESC
    )
    WHERE ROWNUM = 1
  ),
  format => 'ALLSTATS LAST +COST +BYTES +PREDICATE +ALIAS'
))
