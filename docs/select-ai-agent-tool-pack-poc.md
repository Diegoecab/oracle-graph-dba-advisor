# Select AI Agent Tool Pack PoC

## Objetivo

Validar si conviene evolucionar parte del skill desde `RUN_SQL` generico hacia tools diagnosticas registradas dentro de la base y expuestas por Native MCP.

## Alcance de esta PoC

Se implemento un pack minimo de 3 tools para el caso de `plan instability`:

1. `GA_PLAN_INSTABILITY_SUMMARY`
2. `GA_SQL_CHILD_DETAIL`
3. `GA_SQL_PLAN_EVIDENCE`

## Archivos creados

- `clients/adb-plan-instability-tool-pack-poc.sql`
- `workload/newfraud/09_native_mcp_tool_pack_poc.sh`

## Que hace cada tool

### `GA_PLAN_INSTABILITY_SUMMARY`

Devuelve candidatos con señales de:

- multiples child cursors
- multiples plan hashes
- invalidaciones
- churn de parseo

Input:

- `SQL_TEXT_FILTER` opcional
- `LIMIT_ROWS` opcional

### `GA_SQL_CHILD_DETAIL`

Devuelve el detalle por child cursor para un `SQL_ID`.

Input:

- `TARGET_SQL_ID`

### `GA_SQL_PLAN_EVIDENCE`

Devuelve evidencia adicional para un `SQL_ID`:

- razones en `V$SQL_SHARED_CURSOR`
- historia por `V$SQLAREA_PLAN_HASH`

Input:

- `TARGET_SQL_ID`

## Resultado de la validacion

La PoC quedo instalada y validada sobre la ADB de prueba.

Resultado observado:

1. La tool de resumen detecto correctamente el caso `PLAN_INSTABILITY_Q03`.
2. El drill-down por `SQL_ID` devolvio los child cursors esperados.
3. La tool de evidencia devolvio razones y plan hashes en un formato mucho mas limpio para consumo del skill.

Caso validado:

- `SQL_ID`: `687jqhwd6h558`
- `3` child cursors
- `2` `PLAN_HASH_VALUE`
- razones visibles como `Optimizer mismatch` y `Bind mismatch`

## Que mejora frente a RUN_SQL

### Ventajas

1. El skill ya no necesita construir ni inyectar SQL diagnostico para ese playbook.
2. El output queda mas estructurado y predecible.
3. Baja el riesgo de errores de prompt o de variaciones innecesarias en las consultas.
4. Facilita governance, porque el playbook queda empaquetado dentro de la base.

### Costos

1. Hay que desplegar y versionar logica PL/SQL por cada pack diagnostico.
2. Cambiar el playbook requiere cambiar funciones y tools, no solo templates.
3. El troubleshooting del tool pack pasa a tener una capa adicional dentro de la DB.

## Conclusion practica

Si tiene sentido.

No conviene migrar todo el skill de golpe a tools dentro de la base, pero si conviene probar este modelo para los playbooks mas repetibles y de mayor valor, por ejemplo:

1. plan instability
2. top SQL degradadas
3. evidencia de baselines
4. gaps de indices de grafo

## Recomendacion

Modelo recomendado a corto plazo:

1. mantener `RUN_SQL` como fallback universal
2. agregar tools empaquetadas solo para playbooks prioritarios
3. hacer que el skill prefiera la tool empaquetada cuando exista
4. usar `RUN_SQL` solo para exploracion complementaria o casos no cubiertos

## Comando de prueba

Instalacion:

```bash
/mnt/c/DC/Soft/sqlcl-latest/sqlcl/bin/sql -S /nolog @/tmp/install_ga_tool_pack.sql
```

Validacion MCP:

```bash
export RUN_INSTALL=0
export ADB_USERNAME=NEWFRAUD
export ADB_PASSWORD='TxGraph#Advisor_2026X'
bash workload/newfraud/09_native_mcp_tool_pack_poc.sh
```
