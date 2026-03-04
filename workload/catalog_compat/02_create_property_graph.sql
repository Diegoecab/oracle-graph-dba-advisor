--------------------------------------------------------------------------------
-- 02_create_property_graph.sql
-- Catalog Compatibility Graph — Property Graph Definition (Oracle 23ai / 26ai)
--
-- Models product compatibility as a property graph:
--   - Products, Items, and UserProducts are vertices
--   - Compatibility relationships are edges
--   - Enables SQL/PGQ traversals: "find all items compatible with products
--     that are also compatible with item X" (multi-hop compatibility chains)
--------------------------------------------------------------------------------

CREATE PROPERTY GRAPH catalog_compat_graph
  VERTEX TABLES (
    main_product    KEY (product_id)
      LABEL product
      PROPERTIES (product_id, site_id, product_name, category, domain_code, status),

    item            KEY (item_id)
      LABEL item
      PROPERTIES (item_id, site_id, item_title, seller_id, price, condition, status),

    user_product    KEY (user_product_id)
      LABEL user_product
      PROPERTIES (user_product_id, site_id, user_id, product_id, listing_type, status)
  )
  EDGE TABLES (
    compatible_with_item KEY (compatibility_id)
      SOURCE KEY (item_id)         REFERENCES item (item_id)
      DESTINATION KEY (main_product_id) REFERENCES main_product (product_id)
      LABEL compatible_item
      PROPERTIES (compatibility_id, site_id, main_domain_code, source,
                  date_created, reputation_level, note_status, note, claims,
                  restrictions_status),

    compatible_with_user_product KEY (compatibility_id)
      SOURCE KEY (user_product_id)  REFERENCES user_product (user_product_id)
      DESTINATION KEY (main_product_id) REFERENCES main_product (product_id)
      LABEL compatible_user_product
      PROPERTIES (compatibility_id, site_id, main_domain_code, source,
                  date_created, reputation_level, note_status, note, claims,
                  restrictions_status),

    compatible_with_product KEY (compatibility_id)
      SOURCE KEY (main_product_id)        REFERENCES main_product (product_id)
      DESTINATION KEY (secondary_product_id) REFERENCES main_product (product_id)
      LABEL compatible_product
      PROPERTIES (compatibility_id, site_id, main_domain_code, source,
                  date_created, reputation_level, note_status, note, claims,
                  restrictions_status)
  );

PROMPT Property graph CATALOG_COMPAT_GRAPH created successfully.
