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

1. Selecciona el pack diagnostico correcto para el sintoma detectado.
2. Ejecuta consultas read-only predefinidas sobre la base via Native MCP.
3. Identifica la SQL candidata principal.
4. Hace drill-down tecnico sobre esa SQL.
5. Resume el hallazgo en lenguaje natural con evidencia.
6. Propone proximos pasos operativos.

En este caso, el pack usado es:

- `sql-templates/packs/missing-index/`

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
5. Grants directos de observabilidad sobre vistas de performance y catalogo.
6. Tool MCP read-only `RUN_SQL`.
7. Bearer token generado con `GRAPH_DIAG_USER`.

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
7. emite el comando para habilitar MCP cuando la ADB ya existe

Para crear la base, definir primero:

```powershell
$env:ADB_ADMIN_PASSWORD = "<admin password>"
.\lab\provision_downer_adb_always_free.ps1 -ExecuteCreate
```

Para aplicar el tag MCP sobre una ADB ya visible:

```powershell
.\lab\provision_downer_adb_always_free.ps1 -ExecuteMcpTag
```

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
3. `RUN_SQL` rechaza DDL, DML, PL/SQL, comentarios y semicolons.

## Secuencia sugerida para mostrar al cliente

### Paso 1 - Presentar el problema

Explicar que se va a simular una consulta de grafo lenta por falta de indices
fisicos sobre una tabla de aristas.

Prompt sugerido:

```text
Estoy viendo lentitud en Mini-DOWNER. Podrias revisar que esta pasando y decirme cual parece ser la causa principal, con evidencia y una recomendacion concreta?
```

### Paso 2 - Ejecutar el pack diagnostico

El runner MCP read-only es:

```bash
workload/downer/08_missing_index_mcp_demo.sh
```

Variables requeridas:

```bash
export ADB_OCID="<autonomous database ocid>"
export ADB_USERNAME="GRAPH_DIAG_USER"
export ADB_PASSWORD="<graph diag password>"
```

Variables default:

```bash
export ADB_REGION="us-ashburn-1"
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

La remediacion no se ejecuta por MCP.

Para probar impacto, ejecutar como `DOWNER_DEMO`:

```sql
@workload/downer/09_invisible_index_validation.sql
```

Este script:

1. crea indices invisibles sobre `E_USES_DEVICE`
2. habilita `optimizer_use_invisible_indexes` solo en la sesion
3. compara planes `DOWNER_MI_Q01_BASE` y `DOWNER_MI_Q01_INVISIBLE`
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

El caso previo de `plan instability` queda como demo secundaria.

Assets:

- `workload/newfraud/08_setup_plan_instability_lab.sql`
- `workload/newfraud/08_plan_instability_demo.sh`
- `workload/newfraud/08_grant_plan_instability_lab_extras.sql`
- `sql-templates/packs/plan-instability/`

Usarlo cuando el mensaje que se quiera mostrar sea cursor churn, child cursors,
plan hash drift e invalidaciones. Para la demo DOWNER, el caso principal es
`missing-index`.
