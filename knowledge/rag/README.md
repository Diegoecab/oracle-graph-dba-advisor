# RAG — Vectorized Documentation for Deep Retrieval

## What This Is

The curated knowledge in `knowledge/graph-patterns/`, `knowledge/graph-design/`, and `knowledge/optimization-rules/` contains distilled rules and patterns the advisor uses directly. But sometimes the advisor needs precise details from official documentation or internal company docs that aren't covered by the curated files.

This directory provides a **RAG (Retrieval-Augmented Generation) layer** — vectorized documentation that the advisor searches when it needs deeper technical reference.

## Two Knowledge Layers

| Layer | Content | Access | Priority |
|---|---|---|---|
| **Curated** (`knowledge/`) | Distilled rules, patterns, checklists | Read entire file | 1st — always consulted |
| **RAG** (`knowledge/rag/docs/`) | Full Oracle docs, internal standards, PDFs | Semantic search → relevant chunks | 2nd — consulted when curated doesn't cover the question |

The advisor should always prefer curated knowledge (verified, concise) over RAG results (may have noise, may be outdated).

## Recommended Documents to Ingest

**Oracle official (project-provided):**
- Graph Developer's Guide PDF (23.1): full PGX/PGQL reference, performance considerations
  `https://docs.oracle.com/en/database/oracle/property-graph/23.1/spgdg/graph-developers-guide-property-graph.pdf`
- Graph Developer's Guide PDF (25.1): SQL/PGQ focus, tuning, variable-length paths
  `https://docs.oracle.com/en/database/oracle/property-graph/25.1/spgdg/graph-developers-guide-property-graph.pdf`
- GRAPH_TABLE SQL Reference (26ai)
- SQL/PGQ Compliance reference

**User-provided (add your own):**
- Internal database standards and naming conventions
- Company-specific graph design documents
- Past tuning runbooks and post-mortems
- Industry-specific compliance requirements

## How to Ingest

### Option A: Oracle ADB with OracleVS (recommended for enterprise)

If you have the Oracle ADB memory backend (`memory/backends/oracle-adb-memory.md`), use the same ADB instance for RAG. Ingest with `langchain-oracledb`:

```python
from langchain_oracledb import OracleVS, OracleTextSplitter, OracleEmbeddings

# Chunk by document sections, not fixed token windows
splitter = OracleTextSplitter(
    separators=["\n## ", "\n### ", "\n\n", "\n"],
    chunk_size=1500,
    chunk_overlap=200
)

# Store with metadata for filtering
vs = OracleVS(
    connection=conn,
    table_name="ADVISOR_RAG_DOCS",
    embedding=OracleEmbeddings(conn=conn),
    distance_strategy="COSINE"
)
```

### Option B: Local vector store (for development)

Use ChromaDB, FAISS, or any local vector store:

```python
from langchain_community.vectorstores import Chroma
from langchain_community.embeddings import HuggingFaceEmbeddings

vs = Chroma(
    persist_directory="knowledge/rag/.vectorstore",
    embedding_function=HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
)
```

### Option C: File-based (no vector search)

Place docs in `knowledge/rag/docs/` as markdown. The advisor reads them when referenced. No semantic search — just file access. Works with any MCP client that has filesystem tools.

## Chunking Best Practices for Oracle Docs

- **Chunk by section hierarchy**, not fixed tokens. Oracle docs have clear `##` / `###` structure
- **Preserve heading path as metadata**: `{"section": "Chapter 5 > Tuning > Variable Length Paths", "version": "25.1"}`
- **Filter by version at query time**: always include `version` in metadata so the advisor retrieves docs matching the user's database version
- **Use hybrid search**: Vector similarity + BM25 keyword. Oracle-specific terms (`ORA-01555`, `DBMS_STATS`, `GRAPH_TABLE`) need exact match — vector search alone misses them

## Directory Structure

```
knowledge/rag/
├── README.md          # This file (committed)
├── docs/              # Raw documents (gitignored)
│   ├── oracle/        # Oracle official docs (PDFs, HTML)
│   └── custom/        # User-added company docs
└── .vectorstore/      # Local vector index if using Option B (gitignored)
```

## Privacy

The `docs/` and `.vectorstore/` directories are gitignored. They may contain proprietary documentation. Do not commit to public repositories.
