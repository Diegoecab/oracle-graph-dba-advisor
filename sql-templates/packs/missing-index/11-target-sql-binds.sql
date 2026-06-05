SELECT
  sql_id,
  child_number,
  name,
  position,
  datatype_string,
  value_string,
  was_captured,
  last_captured
FROM v$sql_bind_capture
WHERE sql_id = '__SQL_ID__'
ORDER BY child_number DESC, position
