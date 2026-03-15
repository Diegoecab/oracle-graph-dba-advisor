# Knowledge Extensions

This directory contains domain-specific graph patterns, optimization rules, and Oracle internals documentation that extend the advisor's base knowledge in `SYSTEM_PROMPT.md`.

A consolidated summary of all recommendations can be found in [`recommendations-guide.md`](recommendations-guide.md).

## Directory Structure

```
knowledge/
├── README.md                              # This file
├── graph-patterns/                        # Domain-specific graph query patterns
│   ├── README.md                          # Pattern format specification
│   ├── fraud-detection.md                 # Fraud ring, account takeover, money laundering
│   ├── social-network.md                  # Influence, community, recommendation patterns
│   └── supply-chain.md                    # Logistics, dependency, risk propagation
├── optimization-rules/                    # Advanced indexing and optimization strategies
│   └── advanced-indexing.md               # 7 strategies beyond the base 5
└── oracle-internals/                      # Oracle CBO behavior with GRAPH_TABLE
    ├── pgq-optimizer-behavior.md          # How the optimizer handles SQL/PGQ
    └── official-documentation-reference.md # Feature matrix, translation rules, URLs
```

## How Extensions Work

The advisor reads relevant knowledge files based on the user's graph domain. When a user mentions "fraud graph" or "social network", the advisor loads the corresponding pattern file to enhance its recommendations with domain-specific insights.

## Adding New Patterns

1. Create a new `.md` file in `graph-patterns/`
2. Follow the format specification in `graph-patterns/README.md`
3. Include: pattern name, SQL/PGQ query, performance characteristics, index strategy, anti-patterns
4. The advisor will automatically pick up new files when loaded into the project context

## Adding New Optimization Rules

1. Add new strategies to `optimization-rules/advanced-indexing.md` or create a new file
2. Each strategy should include: when to apply, DDL example, expected impact, trade-offs

## Adding Oracle Internals Notes

1. Add findings to `oracle-internals/pgq-optimizer-behavior.md` or create topic-specific files
2. Include: Oracle version tested, behavior observed, workaround if needed
