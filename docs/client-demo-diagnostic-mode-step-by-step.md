# Demo Step by Step - Diagnostic Mode

## Objetivo de la demo

Mostrar como el skill ayuda al equipo de administracion a diagnosticar un
problema de performance en minutos, usando evidencia concreta de la base y sin
depender de analisis manual ad hoc.

El caso principal de esta demo simula un problema comun en workloads SQL/PGQ:

- una consulta `GRAPH_TABLE` lenta
- un recorrido de grafo sobre una tabla de aristas grande
- `TABLE ACCESS FULL` sobre la arista principal
- falta de indices lideres sobre `SRC` y `DST`
- recomendacion de indices reversibles con evidencia de plan y selectividad

El escenario usa un mini modelo `DOWNER_DEMO` inspirado en metadata real del
cliente, reducido para correr en ADB-S Always Free.

## Ambiente target

La demo se ejecuta en OCI:

1. Tenancy: `latinoamerica`.
2. Perfil OCI CLI: `LATINOAMERICA_APIKEY`.
3. Region: `us-ashburn-1`, porque es el home region `IAD` del tenancy.
4. Compartment: `diego.e.cabrera` creado el `2026-04-10`, identificado porque
   debajo tiene el subcompartment `pitwall`.
5. Base: ADB-S Always Free, nombre sugerido `GADVDOWNERAF`.

Always Free se mantiene como restriccion explicita de la demo. Por eso el
dataset sintetico debe quedar por debajo del envelope de storage disponible y
el paralelismo de pruebas debe ser moderado.

Nota de ejecucion actual, 2026-06-04: la ADB activa de Mini-DOWNER fue creada en
`sa-saopaulo-1` como Developer Tier, no Always Free, con DB name
`F416HUO273AA732K` y OCID
`ocid1.autonomousdatabase.oc1.sa-saopaulo-1.antxeljrfioir7iauszrvqwbv6dsu5pybolkiidctbm53wjecldafli5xmsa`.
Mantener el dataset bajo 20 GB y el workload en 4 workers para conservar la demo
controlada. Ver [mini-downer-demo-database.md](mini-downer-demo-database.md).

URLs operativas de la ADB activa:

- Graph Studio para login con usuario de base `DOWNER_DEMO`:
  `https://JY2OTYFOMIMHAOC-F416HUO273AA732K.adb.sa-saopaulo-1.oraclecloudapps.com/graphstudio/`
- Graph Studio via OCI SSO:
  `https://JY2OTYFOMIMHAOC-F416HUO273AA732K.adb.sa-saopaulo-1.oraclecloudapps.com/graphstudio/?sso=true`
- Database Actions SQL / SQL Developer Web para implementar recomendaciones
  aprobadas fuera del MCP read-only:
  `https://JY2OTYFOMIMHAOC-F416HUO273AA732K.adb.sa-saopaulo-1.oraclecloudapps.com/ords/sql-developer`

## Que problema representa este caso

Este escenario representa un incidente donde una consulta de grafo que deberia
ser selectiva termina leyendo demasiadas filas por ausencia de indices en la
tabla de aristas.

La pregunta operacional es:

1. Cual es la SQL lenta?
2. Que tabla y que paso del plan consume el costo?
3. El full scan es razonable o indica un gap fisico?
4. Falta un indice sobre la direccion de traversal?
5. Que recomendacion puede escalarse al DBA con rollback claro?

## Modelo de demo

Schema sintetico:

- `DOWNER_DEMO`

Property graph:

- `DOWNER_DEMO.DOWNER_GRAPH`

Tablas de nodos:

- `N_USER`
- `N_DEVICE`
- `N_BANK_ACCOUNT`
- `N_CARD`
- `N_IP`

Tablas de aristas:

- `E_USES_DEVICE`
- `E_WITHDRAWAL_BANK_ACCOUNT`
- `E_USES_CARD`
- `E_USES_IP`

El problema se induce de forma controlada:

1. Las aristas secundarias tienen indices sobre `SRC` y `DST`.
2. `E_USES_DEVICE` queda intencionalmente sin indices lideres sobre `SRC` y
   `DST`.
3. El workload `DOWNER_MI_Q01` busca usuarios que comparten dispositivos con
   `U00000042`.
4. La distribucion de datos crea dispositivos compartidos y fan-in/fan-out
   suficiente para que la falta de indice sea visible.

## Como trabaja el skill

El skill no genera SQL diagnostico improvisado en el momento.

Trabaja con un playbook prearmado y versionado:

1. Hace triage general del contexto, catalogo, SQL candidato, plan, waits y
   metadata de objetos.
2. Selecciona el pack diagnostico correcto solo si la evidencia lo justifica.
3. Ejecuta consultas read-only predefinidas sobre la base via Native MCP.
4. Identifica la SQL candidata principal.
5. Hace drill-down tecnico sobre esa SQL.
6. Resume el hallazgo en lenguaje natural con evidencia.
7. Propone proximos pasos operativos.

En la ejecucion esperada de este laboratorio, la evidencia termina justificando:

- `sql-templates/packs/missing-index/`

El skill no debe elegir ese pack solamente porque el caso se llama
Mini-DOWNER. Si la evidencia indicara otra causa, debe seguir el camino
diagnostico correspondiente.

La misma base tambien puede preparar escenarios secundarios. Para una consulta
especifica con planes cambiantes y desviacion de tiempo, usar `DOWNER_PI_Q01`.
Ese caso debe llevar al pack `sql-templates/packs/plan-instability/` solo si el
skill observa multiple child cursors, distintos `PLAN_HASH_VALUE`,
invalidaciones, bind mismatch, o spread relevante de elapsed/buffer gets para
el mismo SQL.

## Arquitectura operativa del skill

Para el cliente, el flujo es:

1. El usuario admin interactua con el skill.
2. El skill se conecta a la base objetivo mediante ADB Native MCP.
3. MCP expone herramientas controladas hacia la base.
4. El skill ejecuta solo `RUN_SQL`.
5. `RUN_SQL` acepta solo `SELECT` y `WITH`.
6. El skill devuelve diagnostico y recomendacion.

Punto importante:

- el canal de ejecucion es MCP
- el acceso es con un usuario tecnico dedicado
- el diagnostico es read-only
- la remediacion queda separada y sujeta a aprobacion

## Prerrequisitos

Para correr el modo diagnostico del skill en esta demo se necesita:

1. ADB-S Always Free disponible en `us-ashburn-1`.
2. ADB Native MCP habilitado con el tag:
   `adb$feature={"name":"mcp_server","enable":true}`.
3. Usuario owner de laboratorio: `DOWNER_DEMO`.
4. Usuario tecnico de diagnostico: `GRAPH_DIAG_USER`.
5. Role `GRAPH_DEVELOPER` habilitado para `DOWNER_DEMO` si se usara Graph
   Studio.
6. Proxy grant de Graph Studio:
   `ALTER USER DOWNER_DEMO GRANT CONNECT THROUGH GRAPH$PROXY_USER`.
7. Grants directos de observabilidad sobre vistas de performance y catalogo.
8. Tool MCP read-only `RUN_SQL`.
9. Bearer token generado con `GRAPH_DIAG_USER`.

## Setup de OCI y ADB

El helper principal es:

```powershell
.\lab\provision_downer_adb_always_free.ps1
```

Este script:

1. usa el perfil `LATINOAMERICA_APIKEY`
2. valida que el tenancy sea `latinoamerica`
3. confirma que el home region sea `us-ashburn-1`
4. resuelve el compartment `diego.e.cabrera` correcto por el child `pitwall`
5. lista ADBs visibles en el compartment
6. emite el comando de creacion Always Free
7. agrega tags de preservacion contra borrado o shutdown automatico
8. emite el comando para habilitar MCP cuando la ADB ya existe

### Tags obligatorios de preservacion

Este tenancy usa tags de control operativo que pueden apagar o eliminar
recursos automaticamente. La ADB de demo no debe crearse sin validar estos
tags.

El helper aplica y valida estos defined tags en `0-ResourceControl`:

```text
DeleteResource=WeeklyDeleteResourceNo
ShutdownResource=NightlyShutdownNo
KeepResource=Mini-DOWNER demo ADB - preserve for customer demo
ShutdownTime=Manual only
Team=To_be_Assigned
```

Tambien conserva el freeform tag de MCP:

```text
adb$feature={"name":"mcp_server","enable":true}
```

Si una ADB existente aparece con `DeleteResource=WeeklyDeleteResourceYes` o
`ShutdownResource=NightlyShutdownYes`, ejecutar el helper con `-ExecuteMcpTag`
para re-aplicar los tags seguros antes de usarla para la demo.

Para crear la base, definir primero:

```powershell
$env:ADB_ADMIN_PASSWORD = "<admin password>"
.\lab\provision_downer_adb_always_free.ps1 -ExecuteCreate
```

Para aplicar el tag MCP sobre una ADB ya visible:

```powershell
.\lab\provision_downer_adb_always_free.ps1 -ExecuteMcpTag
```

Para incluir tambien el escenario secundario de plan instability durante el
setup automatizado:

```powershell
.\lab\setup_downer_demo_database.ps1 `
  -AutonomousDatabaseId "<adb_ocid>" `
  -AdminPassword "<admin_password>" `
  -DownerPassword "<downer_password>" `
  -GraphDiagPassword "<graph_diag_password>" `
  -SetupPlanInstability
```

Para arrancar directamente la senal de dashboard de plan instability en vez de
la senal de missing-index:

```powershell
.\lab\setup_downer_demo_database.ps1 `
  -AutonomousDatabaseId "<adb_ocid>" `
  -AdminPassword "<admin_password>" `
  -DownerPassword "<downer_password>" `
  -GraphDiagPassword "<graph_diag_password>" `
  -StartPlanInstabilityDashboardLoad
```

No combinar `-StartDashboardLoad` y `-StartPlanInstabilityDashboardLoad`; el
loader de dashboard usa una senal activa por vez.

## Setup de schema y workload

Ejecutar como `ADMIN`:

```sql
@workload/downer/00_create_users.sql "<downer_password>" "<graph_diag_password>"
```

Ejecutar como `DOWNER_DEMO`:

```sql
@workload/downer/01_create_schema.sql
@workload/downer/02_create_property_graph.sql
@workload/downer/03_generate_data.sql
@workload/downer/04_workload_queries.sql
@workload/downer/05_run_workload.sql
@workload/downer/06_lab_summary.sql
```

Ejecutar como `ADMIN` despues de crear las tablas:

```sql
@workload/downer/07_grant_diagnostic_access.sql
```

Ejecutar como `GRAPH_DIAG_USER` para registrar el runtime MCP:

```sql
@clients/adb-native-run-sql-readonly.sql
```

Validacion esperada:

1. `tools/list` expone solo `RUN_SQL`.
2. `RUN_SQL` acepta `SELECT COUNT(*)`.
3. `RUN_SQL` rechaza DDL, DML, PL/SQL, comentarios y terminadores de sentencia
   fuera de literales de texto.
4. `RUN_SQL` acepta texto de recomendacion dentro de un `SELECT`, aunque el
   literal contenga palabras como `CREATE INDEX`, `DROP INDEX`, `FOR UPDATE`,
   `--` o `;`.

## Carga continua para Performance Dashboard

Para que la demo tenga senal visible en ADB Performance Dashboard o Performance
Hub, levantar una carga constante desde la propia base usando `DBMS_SCHEDULER`.
Esto evita depender de muchas terminales cliente y mantiene el control de
sesiones dentro del limite Always Free.

Si `DOWNER_DEMO` ya existia antes de agregar esta capacidad, ejecutar como
`ADMIN`:

```sql
GRANT CREATE JOB TO DOWNER_DEMO;
```

Ejecutar una vez como `DOWNER_DEMO`:

```sql
@workload/downer/10_dashboard_load_setup.sql
```

Arrancar la carga en estado problematico:

```sql
@workload/downer/11_start_dashboard_load_before.sql
```

Para una demo en vivo mas larga, arrancar la misma carga durante 120 minutos:

```sql
@workload/downer/16_start_dashboard_load_before_long.sql
```

Si la demo queda para el dia siguiente o se quiere preservar la senal durante
varios dias, usar el script de 5 dias:

```sql
@workload/downer/17_start_dashboard_load_before_5_days.sql
```

Para la demo coexistente con los tres huecos activos a la vez, usar:

```sql
@workload/downer/27_start_dashboard_load_all_issues_5_days.sql
```

Ese script arranca 4 workers totales: 2 para missing-index
`DOWNER_MI_Q01_DASH_BEFORE`, 1 para supernode/fan-out `DOWNER_SN_Q01_DASH` y 1
para plan-instability `DOWNER_PI_Q01_DASH`.

Defaults:

1. 4 workers.
2. 12 minutos en el script corto, 120 minutos en el script largo, 7200 minutos
   en el script de 5 dias.
3. `anchor_mode = MIXED`.
4. SQL tag: `DOWNER_MI_Q01_DASH_BEFORE`.
5. Module: `MINI_DOWNER_DASHBOARD_LOAD`.

Nota operativa: los scripts de 5 dias son solo para laboratorio o demo.
Mantienen sesiones activas y pueden consumir compute mientras corren,
especialmente en la ADB Developer Tier de Sao Paulo.

Durante la demo, abrir Performance Dashboard y mostrar:

1. carga activa mientras corren los scheduler jobs
2. `DOWNER_MI_Q01_DASH_BEFORE`, `DOWNER_SN_Q01_DASH` y
   `DOWNER_PI_Q01_DASH` en Top SQL o SQL Activity si se usa el script
   coexistente
3. elapsed time / buffer gets altos para missing-index
4. fan-out de `DOWNER_SN_Q01_DASH` sobre `IP00000001`, con paths expandidos
   aunque `E_USES_IP` este indexada
5. child cursor / plan hash / elapsed-spread para `DOWNER_PI_Q01_DASH`
6. evidencia posterior del plan con full scans sobre `E_USES_DEVICE`

Luego ejecutar el skill por MCP read-only. La remediacion se aplica fuera del
canal MCP, como accion lab-only de DBA, desde Database Actions SQL:

`https://JY2OTYFOMIMHAOC-F416HUO273AA732K.adb.sa-saopaulo-1.oraclecloudapps.com/ords/sql-developer`

```sql
@workload/downer/14_apply_visible_index_fix.sql
```

Arrancar la carga post-fix:

```sql
@workload/downer/12_start_dashboard_load_after.sql
```

Senal esperada:

1. `DOWNER_MI_Q01_DASH_AFTER` ejecuta con indices visibles.
2. baja el elapsed time por ejecucion.
3. bajan buffer gets por ejecucion.
4. la SQL puede dejar de ser dominante en Top SQL porque ya no consume tanto.

Stop y rollback:

```sql
@workload/downer/13_stop_dashboard_load.sql
@workload/downer/15_rollback_visible_index_fix.sql
```

## Secuencia sugerida para mostrar al cliente

### Paso 1 - Presentar el problema

Explicar que se va a simular una consulta de grafo lenta por falta de indices
fisicos sobre una tabla de aristas. Si se usa Performance Dashboard, dejar
corriendo `DOWNER_MI_Q01_DASH_BEFORE` mientras se presenta el problema.

Prompt sugerido:

```text
Usa el skill oracle-graph-dba-advisor y exclusivamente el MCP graph-mini-fraud-downer-26ai.

Estoy viendo lentitud en el grafo Mini-DOWNER y Performance Hub muestra carga constante. Ayudame a entender que esta pasando y que recomendacion concreta le pasarias al DBA. No ejecutes cambios.
```

Buena practica: el primer mensaje tecnico del skill debe mostrar el contexto de
conexion antes de leer performance. Antes de ese SQL de contexto, si el cliente
tiene varios MCPs de base de datos visibles y el prompt no nombra uno exacto,
el skill debe listar los MCPs ADB/SQL candidatos y pedir que el usuario elija
uno. Si el usuario nombra un alias que no existe, el skill debe mostrar los
candidatos visibles o el match cercano, pero no debe elegir por fuzzy match sin
confirmacion. Esto evita diagnosticar otra ADB por memoria vieja, configs
locales stale o aliases parecidos. Si el contexto no coincide con Mini-DOWNER,
el skill debe detenerse y pedir confirmacion.

Para ADB Native MCP, un alias que solo expone `authenticate` o `authorize`
porque todavia no esta autenticado sigue contando como candidato de base de
datos. El skill debe listarlo como `needs authentication`; no debe seleccionar
automaticamente el alias primario solo porque ese ya expone `RUN_SQL`, salvo que
el prompt haya nombrado exactamente ese alias primario.

El usuario no necesita pedir SQL_IDs, clases de problema ni formato de reporte.
El skill debe hacer broad triage por defecto y reportar cobertura para
missing-index, supernode/fan-out y plan-instability aunque solo una causa tenga
evidencia en la ventana inspeccionada.

El `Recommendation Summary` final debe usar categorias estables en todos los
clientes: `Indexing`, `Supernode/Fan-out`, `Plan Stability`,
`Statistics & Optimizer`, `Query Rewriting`, `Graph Design / Modeling`,
`Schema & Architecture`, `Resource / Health` y `Auto Indexing`. Las filas
`PROPOSED` o `DONE` van primero. Las categorias sin evidencia se incluyen como
`SKIPPED`, con una evidencia corta que explique por que no aplican o que dato
no estuvo visible.

### Troubleshooting MCP en Claude

Si Claude Code muestra una URL de autorizacion como:

```text
https://dataaccess.adb.sa-saopaulo-1.oraclecloudapps.com/adb/auth/v1/mcp/databases/.../authorize?...redirect_uri=http://localhost:<port>/callback...
```

eso es esperado. Abrir la URL completa en el navegador, autenticar con
`GRAPH_DIAG_USER`, esperar el callback local y volver a Claude Code. Luego usar
`/mcp` para confirmar que `graph-mini-fraud-downer-26ai` esta conectado y que
expone `RUN_SQL`.

Si Claude Desktop responde que no hay canal SQL disponible y lista solo Gmail,
Drive, Slack, GitHub u otros conectores generales, el skill fue cargado pero la
ADB no esta conectada a esa conversacion. Agregar el conector remoto de ADB MCP
en Claude `Customize > Connectors`, o configurar `mcp-remote` en
`claude_desktop_config.json`, reiniciar Claude Desktop y habilitar ese conector
en el chat antes de pedir el diagnostico.

Si el alcance de la demo incluye breakdown DB time vs DB CPU, pedir/aplicar este
grant antes de usar `OPTIONAL-02C`:

```sql
GRANT SELECT ON SYS.V_$SYS_TIME_MODEL TO GRAPH_DIAG_USER;
```

Si `RUN_SQL` devuelve `ORA-00942` sobre `SYS.V_$SYS_TIME_MODEL`, no detener el
diagnostico. Ese probe corresponde a `OPTIONAL-02C`, una metrica opcional de DB
time model que no forma parte del health path default. Actualizar el skill a la
version vigente y continuar con los `HEALTH-*` default; el resumen final puede
mencionar que `OPTIONAL-02C` no estuvo visible.

Para Mini-DOWNER, el MCP remoto correcto es:

```text
https://dataaccess.adb.sa-saopaulo-1.oraclecloudapps.com/adb/mcp/v1/databases/ocid1.autonomousdatabase.oc1.sa-saopaulo-1.antxeljrfioir7iauszrvqwbv6dsu5pybolkiidctbm53wjecldafli5xmsa
```

Si se usa bearer token estatico en lugar de OAuth, el token dura 1 hora desde
su emision. Generarlo justo antes de la demo, actualizar `ADB_MCP_TOKEN` y
reiniciar o reconectar el cliente MCP. Si durante la demo el MCP empieza a
fallar por autenticacion, asumir primero token expirado.

Si Claude Code muestra `Got new credentials, but ... rejected them on reconnect`,
validar que la entrada no haya quedado mezclando OAuth con un header bearer
viejo:

```powershell
claude mcp get graph-mini-fraud-downer-26ai
```

Si aparece `Authorization: Bearer ...`, limpiar y re-agregar sin header:

```powershell
claude mcp remove graph-mini-fraud-downer-26ai --scope user
claude mcp add --transport http --scope user `
  graph-mini-fraud-downer-26ai `
  "https://dataaccess.adb.sa-saopaulo-1.oraclecloudapps.com/adb/mcp/v1/databases/ocid1.autonomousdatabase.oc1.sa-saopaulo-1.antxeljrfioir7iauszrvqwbv6dsu5pybolkiidctbm53wjecldafli5xmsa"
```

Despues reiniciar Claude Code, ejecutar `/mcp` y autenticar nuevamente con
`GRAPH_DIAG_USER`.

No confundir el skill con el MCP: el skill aporta metodologia; el MCP aporta el
tool `RUN_SQL` que permite consultar la ADB.

### Paso 2 - Ejecutar el camino diagnostico

Durante la demo conversacional, el skill debe seleccionar el camino con base en
la evidencia. Para validar el laboratorio de missing-index de forma directa, el
runner MCP read-only es:

```bash
workload/downer/08_missing_index_mcp_demo.sh
```

Variables requeridas:

```bash
export ADB_OCID="ocid1.autonomousdatabase.oc1.sa-saopaulo-1.antxeljrfioir7iauszrvqwbv6dsu5pybolkiidctbm53wjecldafli5xmsa"
export ADB_USERNAME="GRAPH_DIAG_USER"
export ADB_PASSWORD="<graph diag password>"
```

Variables default:

```bash
export ADB_REGION="sa-saopaulo-1"
export SQL_TAG="DOWNER_MI_Q01"
export GRAPH_OWNER="DOWNER_DEMO"
export GRAPH_NAME="DOWNER_GRAPH"
export EDGE_TABLE="E_USES_DEVICE"
```

### Paso 3 - Mostrar candidato principal

El pack ejecuta:

- `01-candidate-sql.sql`
- `02-primary-sqlid.sql`

Evidencia esperada:

1. `DOWNER_MI_Q01` aparece en `V$SQL`.
2. Hay un `SQL_ID` principal.
3. El ranking muestra elapsed time y buffer gets.

### Paso 4 - Mostrar evidencia de plan

El pack ejecuta:

- `03-hot-plan-operations.sql`

Evidencia esperada:

1. `E_USES_DEVICE` aparece en operaciones del plan.
2. Hay `TABLE ACCESS FULL` sobre la arista target.
3. La operacion concentra buffer gets o elapsed time.

### Paso 5 - Mostrar gap fisico

El pack ejecuta:

- `04-edge-fk-leading-index-gap.sql`

Evidencia esperada:

1. `E_USES_DEVICE.SRC` aparece como `MISSING_LEADING_INDEX`.
2. `E_USES_DEVICE.DST` aparece como `MISSING_LEADING_INDEX`.
3. Las otras aristas sirven como contraste porque tienen indices lideres.

### Paso 6 - Mostrar selectividad y fan-out

El pack ejecuta:

- `05-degree-selectivity.sql`

Evidencia esperada:

1. El edge table tiene volumen suficiente para que el full scan sea relevante.
2. El acceso por `SRC` es selectivo para el usuario ancla.
3. El acceso por `DST` es relevante por dispositivos compartidos.

### Paso 7 - Traducir a conclusion operativa

El pack ejecuta:

- `06-recommendations.sql`

Conclusion esperada:

```text
La consulta DOWNER_MI_Q01 realiza un traversal selectivo sobre E_USES_DEVICE,
pero el plan evidencia full scans sobre la arista target. El catalogo del grafo
muestra que SRC y DST no estan cubiertos como columnas lideres de un indice.
La recomendacion es validar indices invisibles sobre (SRC, END_DATE, DST) y
(DST, END_DATE, SRC), medir buffer gets/elapsed time y luego promover la
remediacion con aprobacion DBA.
```

## Validacion lab-only de remediacion

La remediacion no se ejecuta por MCP. Usar Database Actions SQL / SQL Developer
Web para correr estos scripts con el usuario adecuado:

`https://JY2OTYFOMIMHAOC-F416HUO273AA732K.adb.sa-saopaulo-1.oraclecloudapps.com/ords/sql-developer`

Para probar impacto, ejecutar como `DOWNER_DEMO`:

```sql
@workload/downer/09_invisible_index_validation.sql
```

Para una version exacta y autocontenida del `EXPLAIN PLAN`, ejecutar:

```sql
@workload/downer/28_missing_index_exact_plan_validation.sql
```

Este script:

1. crea indices invisibles sobre `E_USES_DEVICE`
2. habilita `optimizer_use_invisible_indexes` solo en la sesion
3. compara planes `DOWNER_MI_Q01_BASE` / `DOWNER_MI_Q01_EXACT_BASE` y
   `DOWNER_MI_Q01_INVISIBLE` / `DOWNER_MI_Q01_EXACT_INVISIBLE`
4. compara elapsed time, buffer gets y plan hash entre
   `DOWNER_MI_Q01_BASE_RUN` y `DOWNER_MI_Q01_INVISIBLE_RUN`

DDL esperado para validar:

```sql
CREATE INDEX idx_e_uses_device_src_ed_dst
  ON e_uses_device (src, end_date, dst)
  INVISIBLE;

CREATE INDEX idx_e_uses_device_dst_ed_src
  ON e_uses_device (dst, end_date, src)
  INVISIBLE;
```

Rollback:

```sql
DROP INDEX idx_e_uses_device_src_ed_dst;
DROP INDEX idx_e_uses_device_dst_ed_src;
```

## Que demuestra especificamente esta demo

Esta demo demuestra que el skill puede:

1. conectarse por MCP a una ADB objetivo
2. ejecutar diagnostico read-only
3. identificar una SQL de grafo lenta
4. mapear el problema a operaciones relacionales del plan
5. detectar gaps de indices en aristas de un property graph
6. generar recomendacion accionable con rollback

## Que no demuestra esta demo

Esta demo no intenta demostrar:

1. tuning automatico
2. remediacion automatica sin aprobacion
3. reemplazo del DBA
4. cobertura total de todos los incidentes de performance

Su objetivo es mostrar una primera capacidad concreta y de alto valor:
diagnosticar rapido y con evidencia.

## Mensaje clave para el cliente

El skill trabaja como una capa de diagnostico operacional para admins.

No depende de preguntas vagas ni de SQL armado en vivo. Usa playbooks tecnicos
empaquetados, ejecuta evidencia contra la base real via MCP, y devuelve una
conclusion util para acelerar troubleshooting y escalar con mejor contexto.

## Anexo interno - Plan instability

El caso `plan instability` queda como demo secundaria dentro de Mini-DOWNER.

Assets:

- `workload/downer/21_grant_plan_instability_extras.sql`
- `workload/downer/22_setup_plan_instability.sql`
- `workload/downer/23_run_plan_instability_workload.sql`
- `workload/downer/24_start_dashboard_load_plan_instability.sql`
- `workload/downer/25_plan_instability_mcp_demo.sh`
- `sql-templates/packs/plan-instability/`

Usarlo cuando el mensaje que se quiera mostrar sea cursor churn, child cursors,
plan hash drift, invalidaciones y desviacion de elapsed time para una SQL
especifica.

Ejecutar como `ADMIN`:

```sql
@workload/downer/21_grant_plan_instability_extras.sql
```

Ejecutar como `DOWNER_DEMO`:

```sql
@workload/downer/22_setup_plan_instability.sql
@workload/downer/23_run_plan_instability_workload.sql
```

Para Performance Dashboard:

```sql
@workload/downer/24_start_dashboard_load_plan_instability.sql
```

Nota: el loader de dashboard mantiene una senal activa por vez. Al iniciar este
caso se detienen los workers `DDASH_%` existentes, por lo que conviene usarlo
despues de capturar la evidencia del caso missing-index.

Tags esperados:

- `DOWNER_PI_Q01`
- `DOWNER_PI_Q01_DASH`

El diagnostico correcto debe seleccionar este pack solo si la evidencia muestra
inestabilidad para el mismo SQL. No debe seleccionarlo por el nombre del
workload.

Validacion lab-only de remediacion:

```sql
@workload/downer/30_plan_instability_stabilization_validation.sql
```

La mitigacion demostrada es estabilizar inputs y ambiente de optimizador para
reducir child cursors, cambios de plan y dispersion de elapsed time. Si luego
se prueba un unico plan mejor, la recomendacion puede escalar a revision DBA de
SQL Plan Management.

## Anexo interno - Supernode / fan-out

El segundo caso recomendado para Mini-DOWNER es `supernode/fan-out`.

Objetivo:

1. demostrar un problema propio de grafos, no solo de indices
2. mostrar que el skill no debe recomendar DDL automaticamente
3. evidenciar que un nodo de grado extremo puede dominar la cardinalidad
4. recomendar mitigaciones de modelo/query/features

En la demo coexistente, este caso no usa `E_USES_DEVICE`, porque esa arista se
reserva para el defecto de missing-index. El supernode usa `E_USES_IP`, que ya
tiene indices lideres, con ancla `IP00000001`. Asi el skill puede distinguir:

- `DOWNER_MI_Q01`: missing-index sobre `E_USES_DEVICE`
- `DOWNER_SN_Q01`: fan-out de alto grado sobre `E_USES_IP`
- `DOWNER_PI_Q01`: inestabilidad de plan sobre el workload de lookup sesgado

Preparacion fuera del canal MCP diagnostico:

```sql
@workload/downer/18_setup_supernode_fanout.sql
@workload/downer/19_run_supernode_workload.sql
```

Para Performance Dashboard:

```sql
@workload/downer/20_start_dashboard_load_supernode.sql
```

Tag esperado:

- `DOWNER_SN_Q01`
- `DOWNER_SN_Q01_DASH`

Pack read-only:

- `sql-templates/packs/supernode-fanout/`

El diagnostico correcto debe seleccionar este pack solo si la evidencia muestra
un nodo de alto grado, expansion excesiva de paths o filas intermedias altas.
No debe seleccionarlo por el nombre del workload.

Validacion lab-only de remediacion:

```sql
@workload/downer/29_supernode_feature_mitigation_validation.sql
```

La mitigacion demostrada es enrutar identificadores de grado extremo a una
feature precomputada (`DOWNER_IP_FANOUT_FEATURES`) y conservar traversal online
para identificadores de grado normal.
