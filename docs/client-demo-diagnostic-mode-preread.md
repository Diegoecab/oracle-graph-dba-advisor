# Oracle Graph Advisor - Diagnostic Mode Preview

## Objetivo de este pre-read

Anticipar al cliente como funciona el skill en un caso real de troubleshooting de performance, antes de la sesion de laboratorio.

Este documento no muestra una idea abstracta. Resume el flujo real validado sobre una ADB de prueba, usando MCP y consultas diagnosticas empaquetadas.

## Que se va a mostrar en la demo

Se va a simular un incidente donde una misma SQL presenta comportamiento inestable:

- mismo `SQL_ID`
- multiples `child cursors`
- multiples `PLAN_HASH_VALUE`
- invalidaciones
- razones tecnicas visibles de no comparticion del cursor

## Como funciona el skill

El skill trabaja en cinco pasos:

1. Recibe una consigna del usuario admin.
2. Se conecta a la base objetivo por MCP.
3. Ejecuta un playbook diagnostico prearmado y read-only.
4. Detecta la SQL candidata y profundiza sobre ese caso.
5. Devuelve una conclusion operativa con evidencia.

Punto importante:

- el skill no improvisa SQL en vivo
- el skill usa consultas tecnicas predefinidas y versionadas
- el skill no necesita permisos de escritura para diagnosticar

## Simulacion de uso

### Lo que pediria el usuario

`Analiza si hay senales de plan instability o cursor churn en esta base`

### Lo que hace el skill internamente

El skill ejecuta este flujo:

1. Consulta resumen de candidatos de inestabilidad.
2. Elige el `SQL_ID` con mejor evidencia.
3. Trae el detalle por child cursor.
4. Revisa causas de no comparticion en `V$SQL_SHARED_CURSOR`.
5. Trae el historial por `PLAN_HASH_VALUE`.
6. Redacta un resumen accionable.

## Simulacion tecnica del caso

### Paso 1 - Resumen inicial

El skill encuentra una SQL candidata con esta señal:

- `SQL_ID`: `687jqhwd6h558`
- `3` child cursors
- `2` plan hashes distintos
- invalidaciones observadas

### Paso 2 - Drill-down sobre la SQL principal

Luego profundiza sobre ese mismo `SQL_ID` y encuentra:

1. `CHILD_NUMBER 0`
   `PLAN_HASH_VALUE 668796629`
2. `CHILD_NUMBER 2`
   `PLAN_HASH_VALUE 895294461`
3. `CHILD_NUMBER 3`
   `PLAN_HASH_VALUE 895294461`

Esto confirma que el mismo cursor padre presenta mas de un plan.

### Paso 3 - Causas tecnicas observadas

El skill revisa las razones de no comparticion y detecta señales como:

1. `Optimizer mismatch`
2. `Bind mismatch`

Eso permite diferenciar rapidamente si el problema apunta a:

- cambio de entorno de optimizacion
- comportamiento distinto por binds
- churn de child cursors

### Paso 4 - Traduccion a diagnostico operativo

El skill devuelve una conclusion como esta:

`Se detecta inestabilidad sobre la misma SQL. Hay multiples child cursors y multiples plan hashes para un mismo SQL_ID. Tambien se observan invalidaciones y razones compatibles con optimizer mismatch y bind mismatch. Recomendacion: revisar consistencia del entorno de optimizacion, comportamiento de binds y, si aplica, evaluar estabilizacion de plan o baseline.`

## Que ve el cliente en la practica

Desde la perspectiva del equipo admin, el flujo es simple:

1. hacen una pregunta operativa
2. el skill consulta la base real
3. el skill muestra evidencia concreta
4. el skill devuelve una conclusion entendible
5. el equipo decide si escala, corrige o profundiza

## Que hace el skill por detras

Por detras, el skill ejecuta un pack diagnostico empaquetado:

1. `01-instability-summary.sql`
   resumen de candidatos
2. `02-primary-sqlid.sql`
   seleccion del `SQL_ID` principal
3. `03-child-detail.sql`
   detalle de child cursors
4. `04-shared-cursor.sql`
   motivos de no comparticion
5. `05-plan-hash.sql`
   historia por `plan hash`

Esto evita depender de investigacion manual desde cero y asegura que el analisis sea repetible.

## Que valor aporta al cliente

Este modo ayuda a:

1. reducir el tiempo de deteccion
2. estandarizar el diagnostico
3. dejar evidencia util para DBA y owners tecnicos
4. acelerar el troubleshooting inicial

## Requisitos minimos del lado cliente

Para usar este modo se necesita:

1. una ADB con MCP habilitado
2. un usuario tecnico dedicado para el skill en esa base
3. grants minimos de observabilidad sobre vistas de performance
4. autenticacion MCP por OAuth o bearer token

## Que significa usuario tecnico dedicado

Significa un usuario de base creado especificamente para el skill:

1. no personal
2. no `ADMIN`
3. con privilegios controlados
4. reutilizable por el equipo admin

## Como se conecta

El skill se conecta al endpoint MCP de la base objetivo.

Opciones de autenticacion:

1. `OAuth`
   login interactivo desde el cliente MCP
2. `Bearer token`
   token emitido para el usuario tecnico y enviado en el header `Authorization`

## Mensaje clave

El skill funciona como una capa de diagnostico operacional para admins.

No reemplaza el analisis profundo cuando hace falta, pero reduce drasticamente el tiempo para encontrar evidencia, acotar el problema y llegar a una hipotesis accionable.

## Referencias internas

- `docs/client-demo-diagnostic-mode-step-by-step.md`
- `docs/diagnostic-mode-minimum-prereqs.md`
- `workload/newfraud/08_plan_instability_demo.sh`
