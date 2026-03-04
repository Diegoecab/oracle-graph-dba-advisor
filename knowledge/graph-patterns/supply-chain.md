# Supply Chain — Graph Patterns

Patterns for logistics networks, dependency tracking, risk propagation, and bill-of-materials analysis on Oracle SQL/PGQ.

---

## Pattern 1: Supplier Dependency Chain (Multi-hop BOM)

**Graph Pattern**:
```
(product) -[e1 IS requires]-> (component) -[e2 IS supplied_by]-> (supplier)
```

**SQL/PGQ**:
```sql
SELECT * FROM GRAPH_TABLE(supply_graph
  MATCH (p IS product)    -[e1 IS requires]->    (c IS component)
                          -[e2 IS supplied_by]-> (s IS supplier)
  WHERE p.id = :product_id
    AND e1.is_active = 'Y'
  COLUMNS (c.part_number, s.name AS supplier_name, s.country, e1.quantity_required)
);
```

**Performance Characteristics**:
- Hops: 2 (product → component → supplier)
- Edge joins: 2
- Vertex joins: 3
- Fan-out risk: **MEDIUM** — a product may have 50-200 components, each with 1-3 suppliers
- Typical selectivity: `is_active` filters discontinued components

**Index Strategy**:
- `CREATE INDEX idx_requires_src ON requires(src)` — product to components
- `CREATE INDEX idx_supplied_by_src ON supplied_by(src)` — component to suppliers
- Composite: `CREATE INDEX idx_requires_src_active ON requires(src, is_active)` — covers filter + FK
- For BOM explosion (all levels), extend to 3+ hops with cascading FK indexes

**Anti-patterns**:
- BOM hierarchies can be deep (10+ levels) — don't try to do this in a single GRAPH_TABLE with fixed hops
- Use recursive CTE (`WITH RECURSIVE`) for variable-depth BOM traversal, not SQL/PGQ
- Don't forget to handle circular references (component A requires B requires A) with cycle detection

**Real-world frequency**: **HIGH** — core ERP/MRP operation, frequently executed

---

## Pattern 2: Risk Propagation (Cascading Failure)

**Graph Pattern**:
```
(failed_supplier) <-[e1 IS supplied_by]- (component) <-[e2 IS requires]- (product)
```

**SQL/PGQ**:
```sql
-- Find all products affected by a supplier disruption
SELECT * FROM GRAPH_TABLE(supply_graph
  MATCH (s IS supplier)   <-[e1 IS supplied_by]- (c IS component)
                          <-[e2 IS requires]-    (p IS product)
  WHERE s.id = :disrupted_supplier_id
    AND e1.is_active = 'Y'
    AND e2.is_active = 'Y'
  COLUMNS (p.id AS product_id, p.name AS product_name, c.part_number,
           c.is_critical, e2.quantity_required)
);
```

**Performance Characteristics**:
- Hops: 2 (reverse direction — from supplier back to products)
- Edge joins: 2
- Vertex joins: 3
- Fan-out risk: **HIGH** — a single supplier may supply 500+ components, each used in 10-50 products
- Key insight: This is a reverse traversal — DST indexes on edge tables are critical

**Index Strategy**:
- `CREATE INDEX idx_supplied_by_dst ON supplied_by(dst)` — reverse: find components by supplier
- `CREATE INDEX idx_requires_dst ON requires(dst)` — reverse: find products by component
- These are the **opposite** FK indexes from Pattern 1 — both directions needed for full coverage
- Composite: `CREATE INDEX idx_supplied_by_dst_active ON supplied_by(dst, is_active)` — filter + reverse FK

**Anti-patterns**:
- Don't assume risk is binary — model severity levels in edge properties
- 2-hop risk propagation may miss indirect dependencies (tier-2 suppliers) — consider extending to 3 hops
- Don't use this for real-time alerting without indexes — full scans on reverse traversals are the #1 bottleneck

**Real-world frequency**: **MEDIUM** — triggered by supply chain disruption events (irregular but critical)

---

## Pattern 3: Logistics Route Optimization (Path Through Warehouses)

**Graph Pattern**:
```
(origin) -[e1 IS ships_to]-> (warehouse) -[e2 IS ships_to]-> (destination)
```

**SQL/PGQ**:
```sql
-- Find all 2-leg routes from origin to destination through warehouses
SELECT * FROM GRAPH_TABLE(logistics_graph
  MATCH (o IS location) -[e1 IS ships_to]-> (w IS location)
                        -[e2 IS ships_to]-> (d IS location)
  WHERE o.id = :origin_id
    AND d.id = :destination_id
    AND e1.is_active = 'Y'
    AND e2.is_active = 'Y'
    AND e1.transit_days + e2.transit_days <= :max_days
  COLUMNS (w.id AS warehouse_id, w.name AS warehouse_name,
           e1.transit_days + e2.transit_days AS total_days,
           e1.cost + e2.cost AS total_cost)
)
ORDER BY total_cost ASC
FETCH FIRST 10 ROWS ONLY;
```

**Performance Characteristics**:
- Hops: 2
- Edge joins: 2
- Vertex joins: 3
- Fan-out risk: **LOW-MEDIUM** — logistics networks are sparser than social/fraud graphs
- Key optimization: both endpoints are bound, so traversal meets in the middle

**Index Strategy**:
- `CREATE INDEX idx_ships_to_src ON ships_to(src)` — outgoing routes from origin
- `CREATE INDEX idx_ships_to_dst ON ships_to(dst)` — incoming routes to destination
- For the "meeting in the middle" strategy, both SRC and DST indexes are equally important
- Composite: `CREATE INDEX idx_ships_to_src_active_dst ON ships_to(src, is_active, dst)` — covers filter + both FKs

**Anti-patterns**:
- Don't hardcode hop count — real logistics may need 3-4 legs
- Don't forget to consider capacity constraints (edge property `capacity`) — a route exists but may be full
- The ORDER BY + FETCH FIRST pattern requires the optimizer to evaluate all paths before sorting — add FIRST_ROWS hint if needed

**Real-world frequency**: **HIGH** — routing is a core operation, often called thousands of times per planning cycle

---

## Pattern 4: Component Commonality Analysis

**Graph Pattern**:
```
(product1) -[e1 IS requires]-> (shared_component) <-[e2 IS requires]- (product2)
```

**SQL/PGQ**:
```sql
-- Find components shared between two product lines
SELECT shared_part, COUNT(*) AS sharing_count
FROM GRAPH_TABLE(supply_graph
  MATCH (p1 IS product) -[e1 IS requires]-> (c IS component)
                        <-[e2 IS requires]- (p2 IS product)
  WHERE p1.category = :category1
    AND p2.category = :category2
    AND p1.id <> p2.id
    AND e1.is_active = 'Y'
    AND e2.is_active = 'Y'
  COLUMNS (c.part_number AS shared_part)
)
GROUP BY shared_part
ORDER BY sharing_count DESC
FETCH FIRST 50 ROWS ONLY;
```

**Performance Characteristics**:
- Hops: 1 (via shared component, from both product lines)
- Edge joins: 2
- Vertex joins: 3
- Fan-out risk: **MEDIUM** — filtered by category, not single product
- Key challenge: vertex predicate on category (not PK) — requires scanning the product table

**Index Strategy**:
- `CREATE INDEX idx_requires_src ON requires(src)` — product to components
- `CREATE INDEX idx_requires_dst ON requires(dst)` — reverse: component to products
- `CREATE INDEX idx_product_category ON product(category)` — vertex filter for category predicate
- Composite: `CREATE INDEX idx_requires_dst_active ON requires(dst, is_active)` — covers reverse filter + FK

**Anti-patterns**:
- If categories are broad (matching >20% of products), the vertex index won't help — full scan is faster
- The GROUP BY generates a hash aggregation — ensure adequate PGA
- Don't use this for real-time — it's an analytical query best suited for batch/reporting

**Real-world frequency**: **LOW** — periodic analysis for procurement optimization and risk assessment
