# Phase 4: SELECTIVITY ANALYSIS — Quantify Index Benefit

**Goal**: For columns identified in Phase 3, determine if an index would actually help.

**Actions**:
1. Get column selectivity and cardinality → `SELECTIVITY-01`
2. Get value distribution for key predicates → `SELECTIVITY-02`
3. Calculate estimated index benefit → Manual calculation
4. Check for composite index opportunities → `SELECTIVITY-03`

**Index Benefit Rules for Graph Queries**:

| Selectivity | Index Benefit | Typical Graph Scenario |
|---|---|---|
| < 1% | **Excellent** | `is_suspicious = 'Y'`, `risk_level = 'HIGH'` |
| 1-5% | **Good** | `created_date > SYSDATE - 30`, `amount > threshold` |
| 5-15% | **Marginal** | `category = 'RETAIL'` (if 6 categories) |
| > 15% | **Unlikely** | `is_active = 'Y'` (if 80% active) |

**Composite index rule for graph edges**:
When a query filters on edge properties AND traverses to specific vertices, a composite index on `(filter_column, destination_key)` or `(filter_column, source_key)` can satisfy both the filter and the join in one index access — this is the highest-impact optimization for graph queries.
