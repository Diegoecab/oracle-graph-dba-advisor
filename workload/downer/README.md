# Mini-DOWNER Missing-Index Workload

Synthetic ADB-S Always Free workload for the customer-facing Diagnostic Mode demo.

The schema mirrors a small subset of the customer-provided DOWNER metadata:

- vertices: `N_USER`, `N_DEVICE`, `N_BANK_ACCOUNT`, `N_CARD`, `N_IP`
- edges: `E_USES_DEVICE`, `E_WITHDRAWAL_BANK_ACCOUNT`, `E_USES_CARD`, `E_USES_IP`
- graph: `DOWNER_DEMO.DOWNER_GRAPH`

The induced issue is deliberate: `E_USES_DEVICE` has no leading index on `SRC`
or `DST`, while the other edge tables do. The tagged query `DOWNER_MI_Q01`
performs a shared-device traversal and should surface full scans on
`E_USES_DEVICE` until the lab-only invisible indexes are tested.

Execution order:

1. Run `00_create_users.sql` as `ADMIN`, passing strong lab passwords:
   `@workload/downer/00_create_users.sql "<downer_password>" "<graph_diag_password>"`.
2. Connect as `DOWNER_DEMO` and run `01_create_schema.sql`.
3. Run `02_create_property_graph.sql`.
4. Run `03_generate_data.sql`.
5. Run `04_workload_queries.sql` for visible SQL examples.
6. Run `05_run_workload.sql` to seed `V$SQL` with `DOWNER_MI_Q01`.
7. Run `06_lab_summary.sql` for object/count validation.
8. Run `07_grant_diagnostic_access.sql` as `ADMIN`.
9. Register `RUN_SQL` as `GRAPH_DIAG_USER` using `clients/adb-native-run-sql-readonly.sql`.
10. Run `08_missing_index_mcp_demo.sh` from WSL/bash to exercise the read-only pack.
11. Optionally run `09_invisible_index_validation.sql` as `DOWNER_DEMO` for lab-only remediation proof.

`03_generate_data.sql` seeds `DBMS_RANDOM` for reproducible data and uses a
compact default volume: 12k users, 1.2k devices, and about 155k total edges.
Increase `scale_factor` only when the ADB has room for a larger diagnostic
sample.
