--------------------------------------------------------------------------------
-- 03_generate_data.sql
-- Catalog Compatibility Graph — Test Data Generation (Oracle 23ai / 26ai)
--
-- Derived from AWR: CATALOGCOMPATSOCIASH3
-- Real volumes: 73M inserts/24h on CWUP, 12M on CWI
-- Test volumes (scale 1): ~100K products, ~200K items, ~150K user_products
--   + ~500K compatibility edges across 3 edge tables
--
-- Distribution:
--   - 6 marketplaces (MLA 35%, MLB 30%, MLM 15%, MLC 10%, MCO 5%, MLU 5%)
--   - ~5 domain codes (CARS_AND_VANS, CELLPHONES, ELECTRONICS, HOME, FASHION)
--   - High fan-out: popular products have 100+ compatible items (supernodes)
--   - 80% of lookups go to MLA+MLB partitions (realistic skew)
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON
SET TIMING ON

DECLARE
  v_scale         NUMBER := 1;
  -- Vertex volumes
  v_products      NUMBER := 100000 * v_scale;
  v_items         NUMBER := 200000 * v_scale;
  v_user_products NUMBER := 150000 * v_scale;
  -- Edge volumes
  v_cwi           NUMBER := 250000 * v_scale;
  v_cwup          NUMBER := 200000 * v_scale;
  v_cwp           NUMBER := 50000  * v_scale;
  -- Site distribution
  TYPE t_sites IS TABLE OF VARCHAR2(10);
  TYPE t_pcts  IS TABLE OF NUMBER;
  v_sites t_sites := t_sites('MLA','MLB','MLM','MLC','MCO','MLU');
  v_pcts  t_pcts  := t_pcts(0.35, 0.65, 0.80, 0.90, 0.95, 1.00); -- cumulative
  -- Domain codes
  TYPE t_domains IS TABLE OF VARCHAR2(50);
  v_domains t_domains := t_domains('CARS_AND_VANS','CELLPHONES','ELECTRONICS','HOME','FASHION');
  --
  v_start TIMESTAMP;

  FUNCTION random_site RETURN VARCHAR2 IS
    v_r NUMBER := DBMS_RANDOM.VALUE;
  BEGIN
    FOR i IN 1..v_sites.COUNT LOOP
      IF v_r < v_pcts(i) THEN RETURN v_sites(i); END IF;
    END LOOP;
    RETURN 'MLA';
  END;

  FUNCTION random_domain RETURN VARCHAR2 IS
  BEGIN
    RETURN v_domains(TRUNC(DBMS_RANDOM.VALUE(1, v_domains.COUNT + 1)));
  END;

  FUNCTION random_note_status RETURN VARCHAR2 IS
    v_r NUMBER := DBMS_RANDOM.VALUE;
  BEGIN
    IF v_r < 0.70 THEN RETURN 'NONE';
    ELSIF v_r < 0.90 THEN RETURN 'NOTE';
    ELSE RETURN 'WARNING';
    END IF;
  END;

  FUNCTION random_reputation RETURN VARCHAR2 IS
    v_r NUMBER := DBMS_RANDOM.VALUE;
  BEGIN
    IF v_r < 0.05 THEN RETURN '1_red';
    ELSIF v_r < 0.15 THEN RETURN '2_orange';
    ELSIF v_r < 0.35 THEN RETURN '3_yellow';
    ELSIF v_r < 0.70 THEN RETURN '4_light_green';
    ELSE RETURN '5_green';
    END IF;
  END;

BEGIN
  v_start := SYSTIMESTAMP;
  DBMS_OUTPUT.PUT_LINE('=== Catalog Compat data generation started ===');
  DBMS_OUTPUT.PUT_LINE('Scale: ' || v_scale);

  -------------------------------------------------------------------
  -- VERTICES
  -------------------------------------------------------------------
  DBMS_OUTPUT.PUT_LINE('Generating ' || v_products || ' products...');
  INSERT /*+ APPEND */ INTO main_product (product_id, site_id, product_name, category, domain_code, status, created_date)
  SELECT
    LEVEL,
    CASE
      WHEN DBMS_RANDOM.VALUE < 0.35 THEN 'MLA'
      WHEN DBMS_RANDOM.VALUE < 0.65 THEN 'MLB'
      WHEN DBMS_RANDOM.VALUE < 0.80 THEN 'MLM'
      WHEN DBMS_RANDOM.VALUE < 0.90 THEN 'MLC'
      WHEN DBMS_RANDOM.VALUE < 0.95 THEN 'MCO'
      ELSE 'MLU'
    END,
    'Product_' || LPAD(LEVEL, 7, '0'),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,6))
      WHEN 1 THEN 'CARS_AND_VANS' WHEN 2 THEN 'CELLPHONES'
      WHEN 3 THEN 'ELECTRONICS'   WHEN 4 THEN 'HOME'
      ELSE 'FASHION'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,6))
      WHEN 1 THEN 'CARS_AND_VANS' WHEN 2 THEN 'CELLPHONES'
      WHEN 3 THEN 'ELECTRONICS'   WHEN 4 THEN 'HOME'
      ELSE 'FASHION'
    END,
    CASE WHEN DBMS_RANDOM.VALUE < 0.95 THEN 'ACTIVE' ELSE 'INACTIVE' END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 730)
  FROM DUAL CONNECT BY LEVEL <= v_products;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_items || ' items...');
  INSERT /*+ APPEND */ INTO item (item_id, site_id, item_title, seller_id, price, condition, status, created_date)
  SELECT
    LEVEL,
    CASE
      WHEN DBMS_RANDOM.VALUE < 0.35 THEN 'MLA'
      WHEN DBMS_RANDOM.VALUE < 0.65 THEN 'MLB'
      WHEN DBMS_RANDOM.VALUE < 0.80 THEN 'MLM'
      WHEN DBMS_RANDOM.VALUE < 0.90 THEN 'MLC'
      WHEN DBMS_RANDOM.VALUE < 0.95 THEN 'MCO'
      ELSE 'MLU'
    END,
    'Item_' || LPAD(LEVEL, 8, '0'),
    TRUNC(DBMS_RANDOM.VALUE(1, 50000)),
    ROUND(DBMS_RANDOM.VALUE(5, 100000), 2),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,4))
      WHEN 1 THEN 'NEW' WHEN 2 THEN 'USED' ELSE 'REFURBISHED'
    END,
    CASE WHEN DBMS_RANDOM.VALUE < 0.90 THEN 'ACTIVE' ELSE 'PAUSED' END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365)
  FROM DUAL CONNECT BY LEVEL <= v_items;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Generating ' || v_user_products || ' user products...');
  INSERT /*+ APPEND */ INTO user_product (user_product_id, site_id, user_id, product_id, listing_type, status, created_date)
  SELECT
    LEVEL,
    CASE
      WHEN DBMS_RANDOM.VALUE < 0.35 THEN 'MLA'
      WHEN DBMS_RANDOM.VALUE < 0.65 THEN 'MLB'
      WHEN DBMS_RANDOM.VALUE < 0.80 THEN 'MLM'
      WHEN DBMS_RANDOM.VALUE < 0.90 THEN 'MLC'
      WHEN DBMS_RANDOM.VALUE < 0.95 THEN 'MCO'
      ELSE 'MLU'
    END,
    TRUNC(DBMS_RANDOM.VALUE(1, 50000)),
    TRUNC(DBMS_RANDOM.VALUE(1, v_products + 1)),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,5))
      WHEN 1 THEN 'GOLD_SPECIAL' WHEN 2 THEN 'GOLD'
      WHEN 3 THEN 'SILVER' ELSE 'BRONZE'
    END,
    'ACTIVE',
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365)
  FROM DUAL CONNECT BY LEVEL <= v_user_products;
  COMMIT;

  -------------------------------------------------------------------
  -- EDGES: COMPATIBLE_WITH_ITEM
  -- Supernodes: 2% of products get 20x more compatible items
  -------------------------------------------------------------------
  DBMS_OUTPUT.PUT_LINE('Generating ' || v_cwi || ' compatible_with_item edges...');
  INSERT /*+ APPEND */ INTO compatible_with_item
    (item_id, main_product_id, site_id, main_domain_code, source, creation_source,
     date_created, reputation_level, note_status, claims, restrictions_status)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_items + 1)),
    -- Supernodes: 2% of products get heavy connections
    CASE WHEN DBMS_RANDOM.VALUE < 0.15
      THEN TRUNC(DBMS_RANDOM.VALUE(1, GREATEST(v_products * 0.02, 1) + 1))
      ELSE TRUNC(DBMS_RANDOM.VALUE(1, v_products + 1))
    END,
    CASE
      WHEN DBMS_RANDOM.VALUE < 0.35 THEN 'MLA'
      WHEN DBMS_RANDOM.VALUE < 0.65 THEN 'MLB'
      WHEN DBMS_RANDOM.VALUE < 0.80 THEN 'MLM'
      WHEN DBMS_RANDOM.VALUE < 0.90 THEN 'MLC'
      WHEN DBMS_RANDOM.VALUE < 0.95 THEN 'MCO'
      ELSE 'MLU'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,6))
      WHEN 1 THEN 'CARS_AND_VANS' WHEN 2 THEN 'CELLPHONES'
      WHEN 3 THEN 'ELECTRONICS'   WHEN 4 THEN 'HOME'
      ELSE 'FASHION'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,4))
      WHEN 1 THEN 'CATALOG' WHEN 2 THEN 'USER' ELSE 'SYSTEM'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,3))
      WHEN 1 THEN 'API' ELSE 'BATCH'
    END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,6))
      WHEN 1 THEN '1_red' WHEN 2 THEN '2_orange' WHEN 3 THEN '3_yellow'
      WHEN 4 THEN '4_light_green' ELSE '5_green'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,4))
      WHEN 1 THEN 'NONE' WHEN 2 THEN 'NONE' ELSE 'NOTE'
    END,
    TRUNC(DBMS_RANDOM.VALUE(0, 5)),
    CASE WHEN DBMS_RANDOM.VALUE < 0.9 THEN 'NONE' ELSE 'RESTRICTED' END
  FROM DUAL CONNECT BY LEVEL <= v_cwi;
  COMMIT;

  -------------------------------------------------------------------
  -- EDGES: COMPATIBLE_WITH_USER_PRODUCT
  -------------------------------------------------------------------
  DBMS_OUTPUT.PUT_LINE('Generating ' || v_cwup || ' compatible_with_user_product edges...');
  INSERT /*+ APPEND */ INTO compatible_with_user_product
    (user_product_id, main_product_id, site_id, main_domain_code, source, creation_source,
     date_created, reputation_level, note_status, claims, restrictions_status)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_user_products + 1)),
    CASE WHEN DBMS_RANDOM.VALUE < 0.15
      THEN TRUNC(DBMS_RANDOM.VALUE(1, GREATEST(v_products * 0.02, 1) + 1))
      ELSE TRUNC(DBMS_RANDOM.VALUE(1, v_products + 1))
    END,
    CASE
      WHEN DBMS_RANDOM.VALUE < 0.35 THEN 'MLA'
      WHEN DBMS_RANDOM.VALUE < 0.65 THEN 'MLB'
      WHEN DBMS_RANDOM.VALUE < 0.80 THEN 'MLM'
      WHEN DBMS_RANDOM.VALUE < 0.90 THEN 'MLC'
      WHEN DBMS_RANDOM.VALUE < 0.95 THEN 'MCO'
      ELSE 'MLU'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,6))
      WHEN 1 THEN 'CARS_AND_VANS' WHEN 2 THEN 'CELLPHONES'
      WHEN 3 THEN 'ELECTRONICS'   WHEN 4 THEN 'HOME'
      ELSE 'FASHION'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,4))
      WHEN 1 THEN 'CATALOG' WHEN 2 THEN 'USER' ELSE 'SYSTEM'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,3))
      WHEN 1 THEN 'API' ELSE 'BATCH'
    END,
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    CASE TRUNC(DBMS_RANDOM.VALUE(1,6))
      WHEN 1 THEN '1_red' WHEN 2 THEN '2_orange' WHEN 3 THEN '3_yellow'
      WHEN 4 THEN '4_light_green' ELSE '5_green'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,4))
      WHEN 1 THEN 'NONE' WHEN 2 THEN 'NONE' ELSE 'NOTE'
    END,
    TRUNC(DBMS_RANDOM.VALUE(0, 5)),
    CASE WHEN DBMS_RANDOM.VALUE < 0.9 THEN 'NONE' ELSE 'RESTRICTED' END
  FROM DUAL CONNECT BY LEVEL <= v_cwup;
  COMMIT;

  -------------------------------------------------------------------
  -- EDGES: COMPATIBLE_WITH_PRODUCT (product-to-product)
  -------------------------------------------------------------------
  DBMS_OUTPUT.PUT_LINE('Generating ' || v_cwp || ' compatible_with_product edges...');
  INSERT /*+ APPEND */ INTO compatible_with_product
    (main_product_id, secondary_product_id, site_id, main_domain_code, source,
     creation_source, date_created, reputation_level, note_status, claims, restrictions_status)
  SELECT
    TRUNC(DBMS_RANDOM.VALUE(1, v_products + 1)),
    TRUNC(DBMS_RANDOM.VALUE(1, v_products + 1)),
    CASE
      WHEN DBMS_RANDOM.VALUE < 0.35 THEN 'MLA'
      WHEN DBMS_RANDOM.VALUE < 0.65 THEN 'MLB'
      WHEN DBMS_RANDOM.VALUE < 0.80 THEN 'MLM'
      WHEN DBMS_RANDOM.VALUE < 0.90 THEN 'MLC'
      WHEN DBMS_RANDOM.VALUE < 0.95 THEN 'MCO'
      ELSE 'MLU'
    END,
    CASE TRUNC(DBMS_RANDOM.VALUE(1,6))
      WHEN 1 THEN 'CARS_AND_VANS' WHEN 2 THEN 'CELLPHONES'
      WHEN 3 THEN 'ELECTRONICS'   WHEN 4 THEN 'HOME'
      ELSE 'FASHION'
    END,
    'SYSTEM',
    'BATCH',
    SYSTIMESTAMP - DBMS_RANDOM.VALUE(1, 365),
    '5_green',
    'NONE',
    0,
    'NONE'
  FROM DUAL CONNECT BY LEVEL <= v_cwp;
  COMMIT;

  -------------------------------------------------------------------
  -- GATHER STATISTICS
  -------------------------------------------------------------------
  DBMS_OUTPUT.PUT_LINE('Gathering optimizer statistics...');
  DBMS_STATS.GATHER_SCHEMA_STATS(
    ownname          => USER,
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
    method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
    cascade          => TRUE,
    no_invalidate    => FALSE
  );

  DBMS_OUTPUT.PUT_LINE('=== Data generation completed in ' ||
    EXTRACT(MINUTE FROM (SYSTIMESTAMP - v_start)) || ' min ' ||
    ROUND(EXTRACT(SECOND FROM (SYSTIMESTAMP - v_start))) || ' sec ===');
END;
/

-- Summary
SELECT 'VERTICES' AS category, table_name, num_rows
FROM user_tables
WHERE table_name IN ('MAIN_PRODUCT','ITEM','USER_PRODUCT')
UNION ALL
SELECT 'EDGES', table_name, num_rows
FROM user_tables
WHERE table_name LIKE 'COMPATIBLE%'
ORDER BY 1, 2;
