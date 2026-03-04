--------------------------------------------------------------------------------
-- 05_run_workload.sql
-- Catalog Compatibility Graph — Automated Workload Runner
--
-- Simulates realistic mixed workload (reads + writes) derived from AWR:
--   - 40% point lookups (Q01, Q02, Q03, Q05, Q06)
--   - 20% full detail reads (Q04, Q07)
--   - 15% inserts (Q08)
--   - 5%  deletes (Q09)
--   - 20% graph traversals (Q10, Q11, Q12, Q13) — the SQL/PGQ patterns
--
-- AWR showed 73M inserts + 82M selects in 24h. This ratio is ~47% write.
-- We bias slightly more toward reads to showcase graph patterns.
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON
SET TIMING ON

CREATE OR REPLACE PROCEDURE run_catalog_workload (
  p_iterations  IN NUMBER DEFAULT 300,
  p_verbose     IN BOOLEAN DEFAULT FALSE
) AS
  v_item_id       NUMBER;
  v_up_id         NUMBER;
  v_prod_id       NUMBER;
  v_site          VARCHAR2(10);
  v_domain        VARCHAR2(50);
  v_max_item      NUMBER;
  v_max_up        NUMBER;
  v_max_prod      NUMBER;
  v_rand          NUMBER;
  v_cnt           NUMBER;
  v_start         TIMESTAMP;
  -- Counters
  v_q01 NUMBER := 0; v_q02 NUMBER := 0; v_q03 NUMBER := 0;
  v_q04 NUMBER := 0; v_q05 NUMBER := 0; v_q06 NUMBER := 0;
  v_q07 NUMBER := 0; v_q08 NUMBER := 0; v_q09 NUMBER := 0;
  v_q10 NUMBER := 0; v_q11 NUMBER := 0; v_q12 NUMBER := 0;
  v_q13 NUMBER := 0;
  -- Site/domain arrays
  TYPE t_arr IS TABLE OF VARCHAR2(50);
  v_sites   t_arr := t_arr('MLA','MLB','MLM','MLC','MCO','MLU');
  v_domains t_arr := t_arr('CARS_AND_VANS','CELLPHONES','ELECTRONICS','HOME','FASHION');
BEGIN
  SELECT MAX(item_id) INTO v_max_item FROM item;
  SELECT MAX(user_product_id) INTO v_max_up FROM user_product;
  SELECT MAX(product_id) INTO v_max_prod FROM main_product;
  v_start := SYSTIMESTAMP;

  DBMS_OUTPUT.PUT_LINE('=== Catalog Compatibility Workload Started ===');
  DBMS_OUTPUT.PUT_LINE('Iterations: ' || p_iterations);

  FOR i IN 1..p_iterations LOOP
    -- Random parameters
    v_item_id := TRUNC(DBMS_RANDOM.VALUE(1, v_max_item + 1));
    v_up_id   := TRUNC(DBMS_RANDOM.VALUE(1, v_max_up + 1));
    v_prod_id := TRUNC(DBMS_RANDOM.VALUE(1, v_max_prod + 1));
    v_site    := v_sites(TRUNC(DBMS_RANDOM.VALUE(1, v_sites.COUNT + 1)));
    v_domain  := v_domains(TRUNC(DBMS_RANDOM.VALUE(1, v_domains.COUNT + 1)));
    v_rand    := DBMS_RANDOM.VALUE(0, 100);

    IF v_rand < 10 THEN
      -----------------------------------------------------------
      -- Q01: User product compatibilities (10%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt
      FROM GRAPH_TABLE (catalog_compat_graph
        MATCH (up IS user_product) -[c IS compatible_user_product]-> (p IS product)
        WHERE up.user_product_id = v_up_id
          AND c.site_id = v_site AND c.main_domain_code = v_domain
        COLUMNS (p.product_id AS pid)
      );
      v_q01 := v_q01 + 1;

    ELSIF v_rand < 18 THEN
      -----------------------------------------------------------
      -- Q02: Item compatibilities by note_status (8%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt
      FROM GRAPH_TABLE (catalog_compat_graph
        MATCH (i IS item) -[c IS compatible_item]-> (p IS product)
        WHERE i.item_id = v_item_id AND c.site_id = v_site AND c.note_status = 'NONE'
        COLUMNS (c.compatibility_id AS cid)
      );
      v_q02 := v_q02 + 1;

    ELSIF v_rand < 28 THEN
      -----------------------------------------------------------
      -- Q03: All CWUP for user_product (10%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt
      FROM GRAPH_TABLE (catalog_compat_graph
        MATCH (up IS user_product) -[c IS compatible_user_product]-> (p IS product)
        WHERE up.user_product_id = v_up_id
        COLUMNS (c.compatibility_id AS cid)
      );
      v_q03 := v_q03 + 1;

    ELSIF v_rand < 35 THEN
      -----------------------------------------------------------
      -- Q04: Item compat full detail (7%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt
      FROM GRAPH_TABLE (catalog_compat_graph
        MATCH (i IS item) -[c IS compatible_item]-> (p IS product)
        WHERE i.item_id = v_item_id AND c.site_id = v_site AND c.main_domain_code = v_domain
        COLUMNS (p.product_id AS pid)
      );
      v_q04 := v_q04 + 1;

    ELSIF v_rand < 40 THEN
      -----------------------------------------------------------
      -- Q05: Existence check (5%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt FROM (
        SELECT 1 FROM GRAPH_TABLE (catalog_compat_graph
          MATCH (i IS item) -[c IS compatible_item]-> (p IS product)
          WHERE i.item_id = v_item_id AND p.product_id = v_prod_id
            AND c.site_id = v_site AND c.main_domain_code = v_domain
          COLUMNS (c.compatibility_id AS cid)
        ) FETCH FIRST 1 ROWS ONLY
      );
      v_q05 := v_q05 + 1;

    ELSIF v_rand < 48 THEN
      -----------------------------------------------------------
      -- Q06: Item vertex lookup (8%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt FROM (
        SELECT 1 FROM GRAPH_TABLE (catalog_compat_graph
          MATCH (i IS item)
          WHERE i.item_id = v_item_id AND i.site_id = v_site
          COLUMNS (i.item_id AS iid)
        ) FETCH FIRST 1 ROWS ONLY
      );
      v_q06 := v_q06 + 1;

    ELSIF v_rand < 55 THEN
      -----------------------------------------------------------
      -- Q07: Product-to-product compat (7%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt
      FROM GRAPH_TABLE (catalog_compat_graph
        MATCH (p1 IS product) -[c IS compatible_product]-> (p2 IS product)
        WHERE p1.product_id = v_prod_id AND c.site_id = v_site
        COLUMNS (p2.product_id AS pid)
      );
      v_q07 := v_q07 + 1;

    ELSIF v_rand < 70 THEN
      -----------------------------------------------------------
      -- Q08: INSERT compatibility (15%)
      -----------------------------------------------------------
      BEGIN
        INSERT INTO compatible_with_user_product
          (user_product_id, main_product_id, site_id, main_domain_code,
           source, creation_source, date_created, reputation_level,
           note_status, restrictions_status)
        VALUES
          (v_up_id, v_prod_id, v_site, v_domain,
           'CATALOG', 'API', SYSTIMESTAMP, '5_green', 'NONE', 'NONE');
        COMMIT;
        v_q08 := v_q08 + 1;
      EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN NULL; -- skip duplicates
      END;

    ELSIF v_rand < 75 THEN
      -----------------------------------------------------------
      -- Q09: DELETE compatibility (5%)
      -----------------------------------------------------------
      DELETE FROM compatible_with_item
      WHERE compatibility_id IN (
        SELECT compatibility_id FROM compatible_with_item
        WHERE site_id = v_site FETCH FIRST 3 ROWS ONLY
      );
      COMMIT;
      v_q09 := v_q09 + 1;

    ELSIF v_rand < 83 THEN
      -----------------------------------------------------------
      -- Q10: Items sharing compatible products (8%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt FROM (
        SELECT 1 FROM GRAPH_TABLE (catalog_compat_graph
          MATCH (i1 IS item)  -[c1 IS compatible_item]-> (p IS product)
                              <-[c2 IS compatible_item]-  (i2 IS item)
          WHERE i1.item_id = v_item_id AND i1.item_id <> i2.item_id
            AND c1.site_id = v_site AND c2.site_id = v_site
          COLUMNS (i2.item_id AS related_id)
        ) FETCH FIRST 100 ROWS ONLY
      );
      v_q10 := v_q10 + 1;

    ELSIF v_rand < 90 THEN
      -----------------------------------------------------------
      -- Q11: User product to compatible items bridge (7%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt FROM (
        SELECT 1 FROM GRAPH_TABLE (catalog_compat_graph
          MATCH (up IS user_product) -[c1 IS compatible_user_product]-> (p IS product)
                                     <-[c2 IS compatible_item]-          (i IS item)
          WHERE up.user_product_id = v_up_id
            AND c1.site_id = v_site AND c2.site_id = v_site
          COLUMNS (i.item_id AS iid)
        ) FETCH FIRST 200 ROWS ONLY
      );
      v_q11 := v_q11 + 1;

    ELSIF v_rand < 96 THEN
      -----------------------------------------------------------
      -- Q12: Product compatibility chain (6%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt FROM (
        SELECT 1 FROM GRAPH_TABLE (catalog_compat_graph
          MATCH (p1 IS product) -[c1 IS compatible_product]-> (p2 IS product)
                                 -[c2 IS compatible_product]-> (p3 IS product)
          WHERE p1.product_id = v_prod_id AND p1.product_id <> p3.product_id
            AND c1.site_id = v_site AND c2.site_id = v_site
          COLUMNS (p3.product_id AS pid)
        ) FETCH FIRST 100 ROWS ONLY
      );
      v_q12 := v_q12 + 1;

    ELSE
      -----------------------------------------------------------
      -- Q13: Cross-type triangle (4%)
      -----------------------------------------------------------
      SELECT COUNT(*) INTO v_cnt FROM (
        SELECT 1 FROM GRAPH_TABLE (catalog_compat_graph
          MATCH (i1 IS item)    -[c1 IS compatible_item]->    (p1 IS product)
                                 -[c2 IS compatible_product]-> (p2 IS product)
                                <-[c3 IS compatible_item]-     (i2 IS item)
          WHERE i1.item_id = v_item_id AND i1.item_id <> i2.item_id
            AND c1.site_id = v_site AND c2.site_id = v_site AND c3.site_id = v_site
          COLUMNS (i2.item_id AS iid)
        ) FETCH FIRST 50 ROWS ONLY
      );
      v_q13 := v_q13 + 1;
    END IF;

    IF MOD(i, 50) = 0 THEN
      DBMS_OUTPUT.PUT_LINE('Progress: ' || i || '/' || p_iterations);
    END IF;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('=== Catalog Workload Completed ===');
  DBMS_OUTPUT.PUT_LINE('Total time: ' || (SYSTIMESTAMP - v_start));
  DBMS_OUTPUT.PUT_LINE('');
  DBMS_OUTPUT.PUT_LINE('Query distribution:');
  DBMS_OUTPUT.PUT_LINE('  Q01 (UP compat lookup):   ' || v_q01);
  DBMS_OUTPUT.PUT_LINE('  Q02 (Item compat filter):  ' || v_q02);
  DBMS_OUTPUT.PUT_LINE('  Q03 (UP all compats):      ' || v_q03);
  DBMS_OUTPUT.PUT_LINE('  Q04 (Item full detail):    ' || v_q04);
  DBMS_OUTPUT.PUT_LINE('  Q05 (Existence check):     ' || v_q05);
  DBMS_OUTPUT.PUT_LINE('  Q06 (Item lookup):         ' || v_q06);
  DBMS_OUTPUT.PUT_LINE('  Q07 (Prod-to-prod):        ' || v_q07);
  DBMS_OUTPUT.PUT_LINE('  Q08 (INSERT compat):       ' || v_q08);
  DBMS_OUTPUT.PUT_LINE('  Q09 (DELETE batch):        ' || v_q09);
  DBMS_OUTPUT.PUT_LINE('  Q10 (Items shared prod):   ' || v_q10);
  DBMS_OUTPUT.PUT_LINE('  Q11 (UP->Item bridge):     ' || v_q11);
  DBMS_OUTPUT.PUT_LINE('  Q12 (Prod chain 2-hop):    ' || v_q12);
  DBMS_OUTPUT.PUT_LINE('  Q13 (Cross-type triangle): ' || v_q13);
END;
/

EXEC run_catalog_workload(p_iterations => 300, p_verbose => FALSE);
