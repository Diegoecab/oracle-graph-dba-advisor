# Graph Use Case Assessment

## Purpose

This guide helps the advisor evaluate whether a relational workload would benefit from a property graph model, and how to design the graph for a new use case. Use this when the user asks questions like:
- "Would my data benefit from a graph model?"
- "How should I model X as a property graph?"
- "I want to detect fraud / analyze supply chain / build recommendations — where do I start?"

## When to Recommend a Graph

A property graph adds value when the **core questions are about connections and paths**, not just entities and attributes. Assessment criteria:

### Strong Graph Indicators
1. **Path-dependent queries**: "Find all entities connected to X within N hops"
   - Fraud rings, money trails, supply chain dependencies
   - SQL equivalent: recursive CTEs or multiple self-joins — complex and slow
2. **Variable-depth traversal**: "How is A connected to B?" (unknown number of hops)
   - Reachability, shortest path, influence propagation
   - SQL equivalent: CONNECT BY or recursive WITH — limited and rigid
3. **Pattern matching across relationships**: "Find triangles / cycles / fan-out patterns"
   - Community detection, circular transactions, shared attributes
   - SQL equivalent: multiple joins with self-referencing — unreadable at 3+ hops
4. **Relationship-centric filtering**: Queries filter primarily on edge properties (amount, date, type) not just vertex properties
5. **Multi-entity convergence**: "Which entities are connected to BOTH X and Y?"

### Weak Graph Indicators (keep relational)
1. Queries are primarily aggregation (SUM, COUNT, AVG) with GROUP BY — relational wins
2. Data is highly normalized and queries are simple key lookups
3. Relationships are 1:1 or 1:N with no traversal needed
4. No path queries — just "who is the parent of X" (single-hop FK lookup)
5. Write-heavy workload with minimal read patterns involving joins

### Assessment Questions (ask the user)
1. "What questions do you need to answer about your data?"
2. "Do those questions involve following chains of relationships?"
3. "How many hops deep do you typically need to traverse?"
4. "What's your read vs. write ratio for these queries?"
5. "How large is the dataset? (vertices and expected edges)"

## How to Design a New Graph

Once a graph is recommended, follow these steps:

### Step 1: Identify Vertices and Edges

Start from the queries (query-first modeling — see `knowledge/graph-design/modeling-checklist.md` rule #1):
- **Vertices**: The nouns in the user's questions (accounts, customers, products, suppliers)
- **Edges**: The verbs/relationships (transfers_to, purchased, supplied_by, follows)

### Step 2: Map to Existing Tables

Check what relational tables already exist:
- Vertex tables: typically entity tables with a PK (CUSTOMERS, ACCOUNTS, PRODUCTS)
- Edge tables: typically junction/bridge tables or transaction tables (TRANSFERS, ORDERS, FOLLOWS)
- If no edge table exists, the relationship may be implicit (FK on entity table) — may need to create an explicit edge table

### Step 3: Define the Property Graph DDL

```sql
CREATE PROPERTY GRAPH <graph_name>
  VERTEX TABLES (
    <entity_table> KEY (<pk_column>)
      LABEL <vertex_label>
      PROPERTIES (<col1>, <col2>, ...)
  )
  EDGE TABLES (
    <relationship_table>
      KEY (<pk_column>)
      SOURCE KEY (<fk_source>) REFERENCES <source_vertex_table> (<pk>)
      DESTINATION KEY (<fk_dest>) REFERENCES <dest_vertex_table> (<pk>)
      LABEL <edge_label>
      PROPERTIES (<col1>, <col2>, ...)
  );
```

### Step 4: Validate with a Starter Query

Write one GRAPH_TABLE query that answers the user's primary question. Run EXPLAIN PLAN. This immediately reveals:
- Whether the graph model answers the question efficiently
- What indexes are needed on edge FK columns
- Whether the data volumes are manageable

### Step 5: Apply Design Rules

Reference `knowledge/graph-design/modeling-checklist.md` for the 8 modeling rules, and `knowledge/graph-design/physical-design.md` for partitioning and indexing.

## Domain-Specific Starting Points

For common use cases, reference the detailed patterns in `knowledge/graph-patterns/`:

| Use Case | Pattern File | Key Starting Query |
|---|---|---|
| Fraud detection | `fraud-detection.md` | Circular money flow, shared device |
| Social network | `social-network.md` | Influencer detection, friend-of-friend |
| Supply chain | `supply-chain.md` | Critical path, single point of failure |
| **Identity resolution** | (not yet documented) | Shared attributes linking disparate records |
| **Recommendation engine** | (not yet documented) | Collaborative filtering via graph paths |
| **Network/IT topology** | (not yet documented) | Impact analysis, root cause traversal |
| **Knowledge graph / ontology** | (not yet documented) | Entity relationships, hierarchical classification |

When a user's use case matches a known domain, cite the specific pattern file and its recommended indexes.

## What the Advisor Should Produce for a New Use Case

When helping design a new graph:

1. **Assessment**: Is a graph the right model? (cite indicators above)
2. **Graph DDL**: `CREATE PROPERTY GRAPH` referencing existing tables
3. **Starter query**: One GRAPH_TABLE query answering the primary business question
4. **Index recommendations**: Based on the starter query's execution plan
5. **Scaling considerations**: Expected edge volume, fan-out, partitioning needs
6. **Limitations**: What SQL/PGQ can't do for this use case (and whether PGX is needed)
