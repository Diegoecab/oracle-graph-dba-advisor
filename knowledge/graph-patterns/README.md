# Graph Pattern Format Specification

Each pattern file in this directory follows a consistent format to enable the advisor to quickly identify relevant patterns and their optimization strategies.

## Pattern File Structure

```markdown
# Domain Name — Graph Patterns

## Pattern N: Pattern Name

**Graph Pattern** (ASCII diagram):
(a IS label) -[e IS edge_label]-> (b IS label) ...

**SQL/PGQ**:
```sql
SELECT ... FROM GRAPH_TABLE(g MATCH ... COLUMNS ...)
```

**Performance Characteristics**:
- Hops: N
- Edge joins: N
- Vertex joins: N
- Fan-out risk: LOW / MEDIUM / HIGH
- Typical selectivity: X%

**Index Strategy**:
- Primary: index on edge FK / filter column
- Composite: (filter, FK) for combined benefit
- Covering: (filter, FK, projected_columns) to avoid table access

**Anti-patterns**:
- What NOT to do and why

**Real-world frequency**: How often this pattern appears in production workloads (HIGH/MEDIUM/LOW)
```

## Naming Conventions

- File names: `domain-name.md` (lowercase, hyphenated)
- Pattern names: descriptive, starting with the hop count or traversal type
- Index names: `idx_{table}_{columns}` format

## Domain Files

| File | Domain | Patterns |
|------|--------|----------|
| `fraud-detection.md` | Financial fraud | 5 patterns |
| `social-network.md` | Social media / communities | 5 patterns |
| `supply-chain.md` | Logistics / manufacturing | 4 patterns |
