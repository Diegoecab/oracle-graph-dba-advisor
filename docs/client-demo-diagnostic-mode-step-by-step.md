# Demo Step by Step - Diagnostic Mode

## Objetivo de la demo

Mostrar como el skill ayuda al equipo de administracion a diagnosticar un problema de performance en minutos, usando evidencia concreta de la base y sin depender de analisis manual ad hoc.

El caso demo validado simula una situacion de inestabilidad de planes sobre una misma SQL:

- mismo `SQL_ID`
- multiples `child cursors`
- multiples `PLAN_HASH_VALUE`
- invalidaciones
- causas visibles de no comparticion del cursor

## Que problema representa este caso

Este escenario representa un tipo de incidente donde una misma consulta cambia de comportamiento en el tiempo y el equipo necesita responder rapido preguntas como:

1. Hay una SQL con regresion o comportamiento inconsistente?
2. El problema viene de cambio de plan, de child cursors, de binds, o de invalidaciones?
3. Que evidencia concreta justifica escalar al DBA o aplicar una accion correctiva?

## Como trabaja el skill

El skill no genera SQL diagnostico improvisado en el momento.

Trabaja con un playbook prearmado y versionado:

1. Selecciona el pack diagnostico correcto para el sintoma detectado.
2. Ejecuta consultas read-only predefinidas sobre la base via Native MCP.
3. Identifica la SQL candidata principal.
4. Hace drill-down tecnico sobre esa SQL.
5. Resume el hallazgo en lenguaje natural con evidencia.
6. Propone proximos pasos operativos.

En este caso, el pack usado es el de `plan instability`.

## Arquitectura operativa del skill

Para el cliente, el flujo es:

1. El usuario admin interactua con el skill.
2. El skill se conecta a la base objetivo mediante MCP.
3. MCP expone herramientas controladas hacia la base.
4. El skill ejecuta solo herramientas o queries empaquetadas.
5. El skill devuelve diagnostico y recomendacion.

Punto importante:

- el canal de ejecucion es MCP
- el acceso es con un usuario tecnico dedicado
- el diagnostico es read-only
- las acciones de remediacion quedan separadas y sujetas a aprobacion

## Prerrequisitos para este modo

Para correr el modo diagnostico del skill en una base cliente se necesita:

1. Una Autonomous Database con MCP habilitado.
2. Un usuario tecnico dedicado para el skill.
3. Grants minimos de observabilidad sobre vistas de performance.
4. Autenticacion MCP por OAuth o bearer token.

### Que significa un usuario tecnico dedicado

Significa crear un usuario de base especifico para este skill dentro de cada base objetivo.

Ese usuario:

1. no es un usuario personal
2. no es `ADMIN`
3. tiene solo los grants necesarios para diagnostico
4. puede ser usado por el equipo admin
5. se rota y audita como cualquier cuenta tecnica

Modelo recomendado:

1. una base objetivo
2. un schema tecnico dedicado para el skill en esa base
3. el mismo skill apuntando a multiples bases, cada una con su propio schema tecnico

### Grants minimos de observabilidad

Para el modo diagnostico base, el usuario tecnico deberia tener como minimo:

```sql
GRANT CREATE SESSION TO graph_diag_user;
GRANT EXECUTE ON DBMS_XPLAN TO graph_diag_user;

GRANT SELECT ON SYS.V_$SQL TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQLAREA_PLAN_HASH TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQL_PLAN TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQL_PLAN_STATISTICS_ALL TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQL_SHARED_CURSOR TO graph_diag_user;
GRANT SELECT ON SYS.V_$SQLTEXT TO graph_diag_user;
GRANT SELECT ON SYS.V_$PARAMETER TO graph_diag_user;
GRANT SELECT ON SYS.V_$SESSION TO graph_diag_user;
GRANT SELECT ON SYS.V_$SYSMETRIC_HISTORY TO graph_diag_user;
GRANT SELECT ON SYS.V_$SYSTEM_EVENT TO graph_diag_user;
GRANT SELECT ON SYS.V_$SGASTAT TO graph_diag_user;
GRANT SELECT ON SYS.V_$PGASTAT TO graph_diag_user;
```

Notas practicas:

1. estos son los minimos para observabilidad y analisis
2. no incluyen remediacion automatica
3. si luego se quiere analizar baselines de forma mas explicita, se puede sumar `SELECT ON DBA_SQL_PLAN_BASELINES`

### Como se conecta especificamente por MCP

La conexion tiene tres piezas:

1. la URL MCP de la base
2. el usuario tecnico de base
3. un mecanismo de autenticacion

La URL MCP apunta a:

`https://dataaccess.adb.<region>.oraclecloudapps.com/adb/mcp/v1/databases/<database-ocid>`

Sobre autenticacion, hay dos opciones:

1. `OAuth`
   el cliente MCP muestra una pantalla de login y el usuario ingresa sus credenciales de base de datos de forma interactiva
2. `Bearer token`
   se genera un token contra el endpoint de autenticacion de ADB usando el usuario tecnico y luego ese token se envia en el header `Authorization: Bearer <token>`

Para este skill, bearer token suele ser la opcion mas practica cuando se quiere una integracion estable y repetible por base.

Importante:

- para el caso demo de laboratorio se uso un setup sintetico de workload
- eso no forma parte del runtime normal del skill
- en produccion, el modo diagnostico no necesita permisos de escritura para analizar

## Secuencia sugerida para mostrar al cliente

### Paso 1 - Presentar el problema

Explicar que se va a simular un incidente donde una misma consulta presenta comportamiento inestable y obliga normalmente a revisar SQL, planes, child cursors y causas de reparse.

### Paso 2 - Ejecutar el skill en modo diagnostico

Pedir al skill algo como:

`Analiza si hay senales de plan instability o cursor churn en esta base`

El skill entonces:

1. Ejecuta el resumen de candidatos.
2. Ordena por severidad tecnica.
3. Elige el `SQL_ID` mas representativo para drill-down.

### Paso 3 - Mostrar el hallazgo principal

En la validacion actual del demo, el skill detecto una SQL con:

1. `3` child cursors
2. `2` plan hashes distintos
3. invalidaciones
4. razones de no comparticion visibles en `V$SQL_SHARED_CURSOR`

### Paso 4 - Mostrar la evidencia tecnica

El skill profundiza con tres vistas del mismo caso:

1. detalle por `child_number`
2. razones de no comparticion del cursor
3. resumen historico por `plan_hash`

Esto permite responder en minutos:

1. si hubo drift de plan
2. si hubo bind mismatch
3. si hubo optimizer mismatch
4. cuantas invalidaciones se observaron

### Paso 5 - Traducir el hallazgo a una conclusion operativa

El skill devuelve una conclusion de negocio-operacion, por ejemplo:

`La consulta presenta inestabilidad dentro del mismo cursor padre. Se observan multiples child cursors, multiples plan hashes e invalidaciones. Las razones visibles apuntan a optimizer mismatch y bind mismatch. Recomendacion: revisar condiciones de binds, consistencia de entorno de optimizacion y, si aplica, evaluar baseline o estabilizacion del plan.`

### Paso 6 - Explicar el valor para el equipo admin

El mensaje para el cliente deberia ser:

1. el skill reduce el tiempo de deteccion
2. el skill estandariza el diagnostico
3. el skill deja evidencia medible para DBA o owner tecnico
4. el skill evita depender de investigacion manual desde cero

## Que demuestra especificamente esta demo

Esta demo demuestra que el skill puede:

1. conectarse por MCP a una base objetivo
2. ejecutar diagnostico read-only
3. detectar senales reales de inestabilidad de cursores y planes
4. resumir el problema de manera accionable
5. servir como capa intermedia entre el incidente y la intervencion del DBA

## Que no demuestra esta demo

Esta demo no intenta demostrar:

1. tuning automatico
2. remediacion automatica sin aprobacion
3. reemplazo del DBA
4. cobertura total de todos los incidentes de performance

Su objetivo es mostrar una primera capacidad concreta y de alto valor: diagnosticar rapido y con evidencia.

## Mensaje clave para el cliente

El skill trabaja como una capa de diagnostico operacional para admins.

No depende de preguntas vagas ni de SQL armado en vivo. Usa playbooks tecnicos empaquetados, ejecuta evidencia contra la base real via MCP, y devuelve una conclusion util para acelerar troubleshooting y escalar con mejor contexto.

## Anexo interno

Assets usados para esta demo validada:

- `workload/newfraud/08_setup_plan_instability_lab.sql`
- `workload/newfraud/08_plan_instability_demo.sh`
- `workload/newfraud/08_grant_plan_instability_lab_extras.sql`
- `sql-templates/packs/plan-instability/`
