# Phase 2: IDENTIFY — Find the Expensive Graph Queries

**Goal**: Find which SQL/PGQ queries are consuming the most resources.

**Template selection**:
- Use `sql-templates/02-identify.sql` when the SQL connection's
  `CURRENT_SCHEMA` owns the target property graph and the `USER_*` graph
  dictionary views are populated.
- Use `sql-templates/02a-identify-dba.sql` when the connection is a technical
  diagnostic account and the graph is owned by another schema. Replace
  `__GRAPH_OWNER__` with the discovered graph owner from the DBA catalog path
  such as `01b-graph-dba-catalog.sql`. Do not rewrite `USER_PG_ELEMENTS`
  templates ad hoc during analysis.

**Actions**:
1. Top SQL by elapsed time (graph queries only) → `IDENTIFY-01`
2. Top SQL by CPU time (graph queries only) → `IDENTIFY-02`
3. Top SQL by executions × avg_elapsed → `IDENTIFY-03`
4. Get full SQL text for each top offender → `IDENTIFY-04`
5. Classify each query by graph pattern type → Manual analysis

**How to identify graph queries in V$SQL**:
- Look for `GRAPH_TABLE` or `MATCH` in `sql_fulltext`
- Look for references to known edge/vertex table names
- Look for SQL tagged with custom comments (e.g., `/* GRAPH_Q1 */`)

**Pattern Classification** (you must classify each query):
- **Single-hop traversal**: `(a)-[e]->(b)` — 1 edge join, usually fast
- **Multi-hop traversal**: `(a)-[e1]->(b)-[e2]->(c)` — N edge joins, elapsed time multiplies
- **Fan-out pattern**: `(a)-[e]->(b)` where `a` has high degree — many edges per vertex
- **Fan-in pattern**: `(m)<-[e1]-(a)-[e2]->(n)` — convergence through shared vertex
- **Circular/ring**: `(a)-[e1]->(b)-[e2]->(c)-[e3]->(a)` — cycle detection, very expensive
- **Filtered traversal**: Any pattern with WHERE on edge/vertex properties — index candidate
- **Aggregated traversal**: Pattern + GROUP BY/SUM/COUNT — often benefits from covering indexes
