# End-to-End Demo

This demo showcases the advisor's full capability in a single session — from "I have relational data, should I use a graph?" to "here are your indexes, and they hold at 10X scale."

## The Story

You are a financial institution. You have accounts, merchants, devices, and transfer transactions in relational tables. You suspect fraud rings exist in your data but your current SQL queries (self-joins, recursive CTEs) are complex and slow. You ask the advisor: **"Can a graph model help?"**

## What the Advisor Demonstrates

| Phase | Advisor Feature | What It Shows |
|-------|----------------|---------------|
| **1. Assessment** | Consultive mode + health check | Checks DB resources first, then evaluates if a graph model fits — explains WHY |
| **2. Design** | Graph modeling | Proposes vertex/edge tables, naming, key choices, edge directionality — following the modeling checklist |
| **3. Build** | DDL generation | Creates the property graph DDL, explains each label and property choice |
| **4. Populate** | Data generation | Generates realistic synthetic data (power-law degrees, skewed properties, temporal spread) |
| **5. Explore** | Query authoring | Writes GRAPH_TABLE queries that answer the fraud detection questions — shows what the graph can do |
| **6. Diagnose** | Full 6-phase diagnostic | Finds missing indexes, stale stats, suboptimal plans — WITHOUT being asked. Proactive detection |
| **7. Recommend** | Proactive index recommendations | "Before you go to production, create THESE indexes to avoid performance problems" |
| **8. Prove** | Index verification | Shows EXPLAIN PLAN before/after for EACH index — TABLE ACCESS FULL to INDEX RANGE SCAN |
| **9. Scale** | Scalability testing | Grows data to 10X, re-tests — proves recommendations hold under load |
| **10. Report** | Full performance report | 3-column comparison: no-indexes vs with-indexes vs 10X-with-indexes |

## How to Run

Start a conversation with the advisor:

```
I have a financial fraud detection scenario. I have relational tables
with accounts, merchants, devices, and money transfers.

Can you help me evaluate if a property graph would work for this?
If yes, help me design it, build it, populate it with test data,
and then analyze the workload and recommend optimizations.

Use my connected database (confirm it's not production first).
Read the demo script from workload/demo/ as your guide.
```

The advisor drives the entire session — you just confirm DDL and observe.

## Duration

- Assessment + Design + Build: ~10 minutes
- Data generation + Exploration: ~10 minutes
- Diagnostic + Recommendations + Verification: ~15 minutes
- Scalability (10X) + Final report: ~10 minutes
- Total: ~45 minutes

## What It Produces

- A fully designed FRAUD_GRAPH property graph
- ~10K accounts, ~500 merchants, ~2K devices, ~100K transfers (1X)
- 4 representative fraud detection queries with execution plans
- Index recommendations with BEFORE/AFTER proof
- Scalability report at 10X (~1M transfers)
- Recommendations scorecard (which indexes worked, which need redesign)

## Cleanup

At the end, the advisor offers to drop all demo objects.
