# Knowledge Freshness — Maintenance Guide

## Contents
- [How Knowledge Gets Stale](#how-knowledge-gets-stale)
- [Three Layers of Defense](#three-layers-of-defense)
- [Version-Sensitive Facts to Watch](#version-sensitive-facts-to-watch)
- [Cadence](#cadence)

## How Knowledge Gets Stale

Oracle releases new database versions roughly annually. Each release can:
- Change SQL/PGQ feature support (new features, removed limitations)
- Alter CBO behavior (new optimizer transformations, changed defaults)
- Add/modify PGX capabilities
- Change ADB-specific features (auto-scaling behavior, ECPU pricing)

## Three Layers of Defense

### Layer 1: Advisor Self-Check (automatic, every session)

The advisor reads `verified_version` from each knowledge file's frontmatter and compares with the connected database version. If the DB is newer, the advisor flags uncertain facts. No action needed from maintainers — this works out of the box.

### Layer 2: URL Health Check (automated, weekly)

A simple check that all documentation URLs in `official-documentation-reference.md` are still alive. Dead links indicate Oracle restructured their docs — which often means content changed too.

**Manual check** (run anytime):
```bash
# Check all Oracle doc URLs from the reference file
grep -oP 'https://docs\.oracle\.com[^\s`]+' knowledge/oracle-internals/official-documentation-reference.md | \
while read url; do
    status=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    echo "$status $url"
done
```

**Automated** (n8n): See `agent/n8n/workflow-knowledge-review.json` for a weekly URL health check workflow.

### Layer 3: LLM-Assisted Review (semi-automated, per Oracle release)

When Oracle releases a new database version:

1. Fetch the release notes and updated documentation pages
2. Pass them to the LLM alongside the current knowledge file
3. Ask: "What facts in this knowledge file are no longer accurate for [new version]?"
4. The LLM produces a **review report** — not an automatic update
5. A human validates and applies changes

**Review prompt template:**

```
I have a knowledge file for an Oracle Graph DBA advisor.
The file was verified for Oracle {old_version}.
Oracle has released {new_version}.

Here is the current knowledge file:
---
{knowledge_file_content}
---

Here are the relevant sections from the new Oracle documentation:
---
{new_doc_content}
---

Please produce a review report:
1. Which facts in the knowledge file are CONFIRMED still correct?
2. Which facts have CHANGED in the new version? (include the old and new values)
3. Which facts could NOT be verified from the provided documentation?
4. Are there NEW features or behaviors that should be ADDED to the knowledge file?

Format as a checklist I can review and apply.
```

## Version-Sensitive Facts to Watch

These specific facts are most likely to change between Oracle releases. Check these FIRST when a new version comes out:

### SQL/PGQ Feature Support
- [ ] Maximum quantifier upper bound (currently 10)
- [ ] ANY SHORTEST / ALL SHORTEST / ANY CHEAPEST support
- [ ] Path pattern variables
- [ ] COST / TOTAL_COST functions
- [ ] Inline subqueries / LATERAL inside MATCH
- [ ] IS LABELED / PROPERTY_EXISTS / binding_count()

### CBO Behavior
- [ ] GRAPH_TABLE expansion mechanism (pre-optimization rewrite)
- [ ] Hint propagation from COLUMNS clause
- [ ] Adaptive plan behavior with graph patterns
- [ ] Star transformation eligibility for graph patterns

### PGX / Graph Server
- [ ] Availability on ADB-S Serverless
- [ ] PGQL vs SQL/PGQ convergence
- [ ] Supported algorithms list
- [ ] Memory management and property selection

### ADB Features
- [ ] Native MCP Server capabilities and tools
- [ ] Select AI Agent integration
- [ ] Auto-scaling behavior with graph workloads
- [ ] ECPU impact on parallel graph queries

## Cadence

| Action | Frequency | Effort |
|--------|-----------|--------|
| Advisor self-check | Every session (automatic) | Zero |
| URL health check | Weekly (automated) | Zero |
| LLM-assisted review | Per Oracle release (~annually) | 2-4 hours |
| Community contributions | Ongoing (PRs welcome) | Review time |
