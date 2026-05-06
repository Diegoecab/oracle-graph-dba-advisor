# Client Demo Prompts

Use the saved SQLcl connection `graph_demo_myschema` for the live demo.

## Prompt 1 — Consultive Mode (design a graph from scratch)

Copy/paste:

---

I want you to act as a senior Oracle Graph advisor, not just a SQL generator.

I’m preparing a fraud-detection initiative for a regional fintech. Today our analysts rely on relational joins, recursive CTEs, and manual investigations to understand suspicious behavior across users, devices, cards, identities, phones, and bank accounts. The process is slow, hard to explain, and difficult to scale.

Use my connected environment only after you first confirm it is not production.

I want you to work in consultive mode and guide the conversation as if you were in front of a client steering committee:

1. Assess whether a property graph is actually the right fit for this fraud use case, and be explicit about why.
2. Translate the business problem into a graph model:
   vertices, edges, keys, directionality, and the properties that matter.
3. Produce a Mermaid diagram of the proposed graph so I can show the model visually.
4. Explain the main design choices and tradeoffs in plain business language first, then in technical terms.
5. Show 4-6 high-value graph questions this model would answer better than plain relational SQL.
6. Generate the Oracle `CREATE PROPERTY GRAPH` DDL only after the model is clear.
7. Recommend the initial indexing strategy the team should have from day one.
8. Call out limits, anti-patterns, and when I should stay relational instead of using graph.

Keep the tone polished and presentation-ready. I want an answer that I could show directly to a client: clear structure, crisp reasoning, and no filler.

Use `workload/demo/00_demo_script.sql` as background if useful, but drive the conversation as an advisor, not as a script reader.

---

## Prompt 2 — Performance Advisor Mode (analyze a real graph workload)

Copy/paste:

---

Use the saved connection `graph_demo_myschema`.

You are reviewing an existing non-production Oracle property graph environment for a live client demo. The schema already contains a fraud graph (`FRAUD_GRAPH`), seeded data, and executed graph workload patterns.

I want you to behave like a performance specialist brought in before go-live.

Please do this in order:

1. Confirm this is not production and summarize the database context.
2. Run your health check first and tell me if the environment has any immediate CPU, I/O, memory, tablespace, or configuration concerns.
3. Discover the graph topology:
   graph objects, vertex tables, edge tables, row counts, statistics freshness, and existing indexes.
4. Identify the most important graph queries currently visible in the workload and explain which ones matter most.
   If you find the tagged family `DEMO_FRAUD_*` in `V$SQL`, use it as the primary demo workload unless stronger evidence suggests otherwise.
5. Read the execution plans and show me the real root causes, not generic advice.
6. Quantify where index gaps exist, especially on edge-table source/destination keys.
7. Give me the top recommendations in priority order:
   exact DDL, why each change matters, expected benefit, rollback, and any write-overhead tradeoff.
8. If you need my approval before running DDL, stop and ask clearly. Otherwise stay read-only.
9. End with two outputs:
   an executive summary for the client,
   and a technical action plan for the DBA team.

Important:

- Keep the explanation sharp and visual: “this query is scanning 80k edges twice”, “this FK has no leading index”, “this is why latency will grow with volume”.
- Prefer evidence from the actual workload over theoretical best practices.
- If the environment already looks good in one area, say that clearly.
- I want this to feel like a premium architecture and performance review, not a generic chatbot answer.

---
