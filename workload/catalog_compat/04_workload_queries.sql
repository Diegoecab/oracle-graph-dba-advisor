--------------------------------------------------------------------------------
-- 04_workload_queries.sql
-- Catalog Compatibility Graph — Workload Queries (Oracle 23ai / 26ai SQL/PGQ)
--
-- Derived from AWR: CATALOGCOMPATSOCIASH3 (19c relational)
-- Converted to native GRAPH_TABLE / MATCH syntax.
--
-- AWR Pattern Mapping:
--   9vx4g0cpxwdfw (INSERT CWUP)           → Q08 (compatibility creation DML)
--   8bqmta2f9vb7d (SELECT CWUP by UP+site)→ Q01 (user_product compatibilities)
--   74ksw0fy8t037 (SELECT CWI by item+site)→ Q02 (item compatibilities)
--   44b96x0576t5b (SELECT CWUP by UP)     → Q03 (all compatibilities for UP)
--   78zc9a2fbx85u (SELECT CWI full row)   → Q04 (item compat full detail)
--   0b3vgxa6vu26t (CWI existence check)   → Q05 (compatibility exists?)
--   89zj9whdrpwwq (DELETE CWI batch)      → Q09 (batch delete DML)
--   07fnnw6qk1k3s (SELECT ITEM by PK)     → Q06 (item lookup)
--   New graph patterns                    → Q10-Q14 (multi-hop traversals)
--
-- The real value of SQL/PGQ here: multi-hop compatibility chains that were
-- impossible (or very complex) in the original relational model.
--------------------------------------------------------------------------------

SET TIMING ON
SET LINESIZE 200
SET PAGESIZE 100

--------------------------------------------------------------------------------
-- Q01: USER PRODUCT COMPATIBILITIES (point lookup)
-- AWR: 8bqmta2f9vb7d — 62K seconds, 13.3M executions
-- "Find all products compatible with a given user_product in a marketplace"
--------------------------------------------------------------------------------
/* CATALOG_Q01 */ -- User product compatibilities
SELECT * FROM GRAPH_TABLE (catalog_compat_graph
  MATCH (up IS user_product) -[c IS compatible_user_product]-> (p IS product)
  WHERE up.user_product_id = :user_product_id
    AND c.site_id = :site_id
    AND c.main_domain_code = :domain_code
  COLUMNS (
    p.product_id        AS compatible_product_id,
    p.product_name      AS product_name,
    p.category          AS category,
    c.compatibility_id  AS compatibility_id,
    c.reputation_level  AS reputation,
    c.note_status       AS note_status,
    c.date_created      AS date_created
  )
);

--------------------------------------------------------------------------------
-- Q02: ITEM COMPATIBILITIES (point lookup)
-- AWR: 74ksw0fy8t037 — 47K seconds, 4.7M executions
-- "Find compatibility IDs for an item in a marketplace with given note_status"
--------------------------------------------------------------------------------
/* CATALOG_Q02 */ -- Item compatibilities filtered by note_status
SELECT * FROM GRAPH_TABLE (catalog_compat_graph
  MATCH (i IS item) -[c IS compatible_item]-> (p IS product)
  WHERE i.item_id = :item_id
    AND c.site_id = :site_id
    AND c.note_status = :note_status
  COLUMNS (
    c.compatibility_id  AS compatibility_id,
    p.product_id        AS product_id,
    p.product_name      AS product_name,
    c.reputation_level  AS reputation
  )
);

--------------------------------------------------------------------------------
-- Q03: ALL COMPATIBILITIES FOR USER PRODUCT (no site filter)
-- AWR: 44b96x0576t5b — 46K seconds, 71.9M executions (HIGHEST buffer gets)
-- "Find all compatibility IDs for a user_product across all sites"
--------------------------------------------------------------------------------
/* CATALOG_Q03 */ -- All user_product compatibilities (all sites)
SELECT * FROM GRAPH_TABLE (catalog_compat_graph
  MATCH (up IS user_product) -[c IS compatible_user_product]-> (p IS product)
  WHERE up.user_product_id = :user_product_id
  COLUMNS (
    c.compatibility_id  AS compatibility_id,
    p.product_id        AS product_id,
    c.site_id           AS site_id,
    c.main_domain_code  AS domain_code
  )
);

--------------------------------------------------------------------------------
-- Q04: ITEM COMPATIBILITY FULL DETAIL
-- AWR: 78zc9a2fbx85u — 33K seconds, 2.3M executions
-- "Get full compatibility details for an item in a marketplace"
--------------------------------------------------------------------------------
/* CATALOG_Q04 */ -- Item compatibility full detail
SELECT * FROM GRAPH_TABLE (catalog_compat_graph
  MATCH (i IS item) -[c IS compatible_item]-> (p IS product)
  WHERE i.item_id = :item_id
    AND c.site_id = :site_id
    AND c.main_domain_code = :domain_code
  COLUMNS (
    p.product_id            AS product_id,
    p.product_name          AS product_name,
    c.compatibility_id      AS compatibility_id,
    c.date_created          AS date_created,
    c.reputation_level      AS reputation,
    c.note_status           AS note_status,
    c.claims                AS claims,
    c.restrictions_status   AS restrictions_status,
    c.source                AS source
  )
);

--------------------------------------------------------------------------------
-- Q05: COMPATIBILITY EXISTS CHECK
-- AWR: 0b3vgxa6vu26t — 30K seconds, 30.2M executions
-- "Check if a specific item-product compatibility exists"
--------------------------------------------------------------------------------
/* CATALOG_Q05 */ -- Existence check
SELECT * FROM GRAPH_TABLE (catalog_compat_graph
  MATCH (i IS item) -[c IS compatible_item]-> (p IS product)
  WHERE i.item_id = :item_id
    AND p.product_id = :main_product_id
    AND c.site_id = :site_id
    AND c.main_domain_code = :domain_code
  COLUMNS (
    c.compatibility_id AS compatibility_id
  )
)
FETCH FIRST 1 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q06: ITEM LOOKUP (high frequency)
-- AWR: 07fnnw6qk1k3s — 82.2M executions (HIGHEST)
-- "Verify item exists before creating compatibility"
--------------------------------------------------------------------------------
/* CATALOG_Q06 */ -- Item vertex lookup
SELECT * FROM GRAPH_TABLE (catalog_compat_graph
  MATCH (i IS item)
  WHERE i.item_id = :item_id
    AND i.site_id = :site_id
  COLUMNS (
    i.item_id    AS item_id,
    i.site_id    AS site_id,
    i.item_title AS title,
    i.status     AS status
  )
)
FETCH FIRST 1 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q07: PRODUCT-TO-PRODUCT COMPATIBILITY
-- "Find all secondary products compatible with a main product"
--------------------------------------------------------------------------------
/* CATALOG_Q07 */ -- Product-to-product compatibility
SELECT * FROM GRAPH_TABLE (catalog_compat_graph
  MATCH (p1 IS product) -[c IS compatible_product]-> (p2 IS product)
  WHERE p1.product_id = :product_id
    AND c.site_id = :site_id
  COLUMNS (
    p2.product_id       AS secondary_product_id,
    p2.product_name     AS secondary_product_name,
    p2.category         AS secondary_category,
    c.compatibility_id  AS compatibility_id,
    c.reputation_level  AS reputation
  )
);

--------------------------------------------------------------------------------
-- Q08: INSERT COMPATIBILITY (DML — highest elapsed in AWR)
-- AWR: 9vx4g0cpxwdfw — 126K seconds, 73.4M executions
-- "Create a new user_product-to-product compatibility"
-- NOTE: This is relational DML, not a graph query, but it generates
-- load on the edge table and its indexes.
--------------------------------------------------------------------------------
/* CATALOG_Q08 */ -- Insert new compatibility (DML)
INSERT INTO compatible_with_user_product
  (user_product_id, main_product_id, site_id, main_domain_code,
   source, creation_source, date_created, reputation_level,
   note_status, restrictions_status)
VALUES
  (:user_product_id, :main_product_id, :site_id, :domain_code,
   :source, 'API', SYSTIMESTAMP, :reputation,
   'NONE', 'NONE');

--------------------------------------------------------------------------------
-- Q09: BATCH DELETE COMPATIBILITIES (DML)
-- AWR: 89zj9whdrpwwq — 34K seconds, 825K executions
-- "Delete multiple compatibilities by ID (batch operation)"
--------------------------------------------------------------------------------
/* CATALOG_Q09 */ -- Batch delete (DML)
DELETE FROM compatible_with_item
WHERE compatibility_id IN (:id1, :id2, :id3, :id4, :id5);

--------------------------------------------------------------------------------
-- ═══════════════════════════════════════════════════════════════════════
-- GRAPH-NATIVE QUERIES (multi-hop — the real SQL/PGQ value-add)
-- These patterns are NEW: they were too complex to express in the
-- original relational model but are natural in SQL/PGQ.
-- ═══════════════════════════════════════════════════════════════════════
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Q10: 2-HOP ITEM-TO-ITEM COMPATIBILITY (via shared product)
-- "Find all items that are compatible with the same products as item :item_id"
-- Pattern: Item1 -> Product <- Item2 (items that share a compatible product)
-- This is the most natural graph query for this model.
--------------------------------------------------------------------------------
/* CATALOG_Q10 */ -- Items sharing compatible products (2-hop)
SELECT * FROM GRAPH_TABLE (catalog_compat_graph
  MATCH (i1 IS item)  -[c1 IS compatible_item]-> (p IS product)
                      <-[c2 IS compatible_item]-  (i2 IS item)
  WHERE i1.item_id = :item_id
    AND i1.item_id <> i2.item_id
    AND c1.site_id = :site_id
    AND c2.site_id = :site_id
  COLUMNS (
    i2.item_id      AS related_item_id,
    i2.item_title   AS related_item_title,
    i2.price        AS related_item_price,
    p.product_id    AS shared_product_id,
    p.product_name  AS shared_product_name,
    p.category      AS category
  )
)
FETCH FIRST 100 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q11: USER_PRODUCT TO ITEM BRIDGE (3-hop)
-- "Given a user_product, find items compatible with the same products"
-- Pattern: UserProduct -> Product <- Item
-- Useful for: "show compatible listings for this user's product"
--------------------------------------------------------------------------------
/* CATALOG_Q11 */ -- User product to compatible items (bridge)
SELECT * FROM GRAPH_TABLE (catalog_compat_graph
  MATCH (up IS user_product) -[c1 IS compatible_user_product]-> (p IS product)
                             <-[c2 IS compatible_item]-          (i IS item)
  WHERE up.user_product_id = :user_product_id
    AND c1.site_id = :site_id
    AND c2.site_id = :site_id
  COLUMNS (
    i.item_id           AS compatible_item_id,
    i.item_title        AS item_title,
    i.price             AS item_price,
    i.condition         AS item_condition,
    p.product_id        AS via_product_id,
    p.product_name      AS via_product_name,
    c2.reputation_level AS item_reputation,
    c2.note_status      AS item_note_status
  )
)
FETCH FIRST 200 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q12: PRODUCT COMPATIBILITY CHAIN (3-hop)
-- "Find products reachable in 2 hops through product-to-product compatibility"
-- Pattern: Product1 -> Product2 -> Product3
-- Useful for: "extended compatibility recommendations"
--------------------------------------------------------------------------------
/* CATALOG_Q12 */ -- Product compatibility chain (2-hop)
SELECT * FROM GRAPH_TABLE (catalog_compat_graph
  MATCH (p1 IS product) -[c1 IS compatible_product]-> (p2 IS product)
                         -[c2 IS compatible_product]-> (p3 IS product)
  WHERE p1.product_id = :product_id
    AND c1.site_id = :site_id
    AND c2.site_id = :site_id
    AND p1.product_id <> p3.product_id
  COLUMNS (
    p2.product_id   AS intermediate_product_id,
    p2.product_name AS intermediate_product_name,
    p3.product_id   AS extended_product_id,
    p3.product_name AS extended_product_name,
    p3.category     AS extended_category
  )
)
FETCH FIRST 100 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q13: CROSS-TYPE COMPATIBILITY TRIANGLE
-- "Find triangles: Item compatible with Product1, Product1 compatible with
--  Product2, Product2 compatible with another Item"
-- Expensive pattern — tests optimizer with 4 edge joins
--------------------------------------------------------------------------------
/* CATALOG_Q13 */ -- Cross-type compatibility triangle
SELECT * FROM GRAPH_TABLE (catalog_compat_graph
  MATCH (i1 IS item)    -[c1 IS compatible_item]->    (p1 IS product)
                         -[c2 IS compatible_product]-> (p2 IS product)
                        <-[c3 IS compatible_item]-     (i2 IS item)
  WHERE i1.item_id = :item_id
    AND c1.site_id = :site_id
    AND c2.site_id = :site_id
    AND c3.site_id = :site_id
    AND i1.item_id <> i2.item_id
  COLUMNS (
    i2.item_id      AS related_item_id,
    i2.item_title   AS related_item_title,
    p1.product_id   AS via_product1_id,
    p2.product_id   AS via_product2_id,
    p2.category     AS target_category
  )
)
FETCH FIRST 50 ROWS ONLY;

--------------------------------------------------------------------------------
-- Q14: HIGH-CLAIMS COMPATIBILITY NEIGHBORS
-- "Find products with high-claims items (quality issues) in the compatibility
--  network of a given product"
-- Filtered traversal — candidate for index on claims column
--------------------------------------------------------------------------------
/* CATALOG_Q14 */ -- High-claims compatibility analysis
SELECT p.product_id, p.product_name, p.category,
       COUNT(*) AS high_claim_compatibilities,
       SUM(claims) AS total_claims
FROM GRAPH_TABLE (catalog_compat_graph
  MATCH (p1 IS product) <-[c IS compatible_item]- (i IS item)
  WHERE p1.product_id = :product_id
    AND c.site_id = :site_id
    AND c.claims > 2
  COLUMNS (
    i.item_id  AS item_id,
    c.claims   AS claims
  )
) gt
CROSS JOIN GRAPH_TABLE (catalog_compat_graph
  MATCH (p IS product)
  WHERE p.product_id = :product_id
  COLUMNS (p.product_id AS product_id, p.product_name AS product_name, p.category AS category)
) pinfo
GROUP BY p.product_id, p.product_name, p.category;
