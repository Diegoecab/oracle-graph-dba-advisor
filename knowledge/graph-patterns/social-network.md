---
verified_version: "23ai"
last_verified: "2026-03-09"
oracle_doc_urls: []
next_review: "on_new_oracle_release"
confidence: "high"
---

# Social Network — Graph Patterns

Patterns for social media, community detection, influence propagation, and recommendation systems on Oracle SQL/PGQ.

## Contents
- [Pattern 1: Mutual Friends (Common Neighbors)](#pattern-1-mutual-friends-common-neighbors)
- [Pattern 2: Influence Propagation (N-hop Reach)](#pattern-2-influence-propagation-n-hop-reach)
- [Pattern 3: Community Detection (Dense Subgraph)](#pattern-3-community-detection-dense-subgraph)
- [Pattern 4: Content Recommendation (Collaborative Filtering)](#pattern-4-content-recommendation-collaborative-filtering)
- [Pattern 5: Shortest Path Approximation (BFS-like)](#pattern-5-shortest-path-approximation-bfs-like)

---

## Pattern 1: Mutual Friends (Common Neighbors)

**Graph Pattern**:
```
(u1) -[e1 IS follows]-> (friend) <-[e2 IS follows]- (u2)
```

**SQL/PGQ**:
```sql
SELECT * FROM GRAPH_TABLE(social_graph
  MATCH (u1 IS user) -[e1 IS follows]-> (friend IS user)
                     <-[e2 IS follows]- (u2 IS user)
  WHERE u1.id = :user1_id
    AND u2.id = :user2_id
    AND e1.is_active = 'Y'
    AND e2.is_active = 'Y'
  COLUMNS (friend.id AS mutual_friend_id, friend.username AS name)
);
```

**Performance Characteristics**:
- Hops: 1 (from each side, meeting at common neighbor)
- Edge joins: 2
- Vertex joins: 3
- Fan-out risk: **HIGH** — popular users may follow thousands of accounts
- Typical selectivity: Both endpoints are bound (u1 AND u2), so the problem is fan-out from both sides

**Index Strategy**:
- `CREATE INDEX idx_follows_src ON follows(src)` — outgoing edges from u1
- `CREATE INDEX idx_follows_dst ON follows(dst)` — incoming edges to u2 (reverse traversal)
- Composite: `CREATE INDEX idx_follows_src_active ON follows(src, is_active)` — covers filter + FK

**Anti-patterns**:
- Don't use this for "people you may know" at scale — enumerate with a batch job, not real-time traversal
- For users with >10K followers, consider a pre-computed mutual friends cache

**Real-world frequency**: **HIGH** — core operation for friend suggestion and profile comparison

---

## Pattern 2: Influence Propagation (N-hop Reach)

**Graph Pattern**:
```
(influencer) -[e1]-> (follower1) -[e2]-> (follower2) -[e3]-> (follower3)
```

**SQL/PGQ**:
```sql
-- 2-hop reach: users reachable within 2 follows
SELECT COUNT(DISTINCT reach_id) FROM GRAPH_TABLE(social_graph
  MATCH (u IS user) -[e1 IS follows]-> (f1 IS user)
                    -[e2 IS follows]-> (f2 IS user)
  WHERE u.id = :influencer_id
    AND e1.is_active = 'Y'
    AND e2.is_active = 'Y'
  COLUMNS (f2.id AS reach_id)
);
```

**Performance Characteristics**:
- Hops: 2 (extensible to N)
- Edge joins: 2 per hop
- Vertex joins: 3
- Fan-out risk: **EXTREME** — 1K followers x 1K followers = 1M paths at 2-hop
- Typical runtime: Highly variable — depends entirely on vertex degree

**Index Strategy**:
- FK indexes on `follows(src)` and `follows(dst)` are mandatory
- For N>2 hops, indexes alone are insufficient — consider:
  - `FETCH FIRST 10000 ROWS ONLY` to cap explosion
  - Pre-computing reach in a materialized view (batch)
  - Using CONNECT BY with NOCYCLE as an alternative for directed acyclic subgraphs

**Anti-patterns**:
- **Never** run unbounded N-hop traversals in real-time — use batch computation
- Avoid COUNT(DISTINCT) on unbounded traversals — materializes the full result before counting

**Real-world frequency**: **LOW** for real-time, **HIGH** for batch analytics

---

## Pattern 3: Community Detection (Dense Subgraph)

**Graph Pattern**:
```
(u1) -[e1]-> (u2) -[e2]-> (u3) -[e3]-> (u1)  -- triangle
```

**SQL/PGQ**:
```sql
SELECT * FROM GRAPH_TABLE(social_graph
  MATCH (u1 IS user) -[e1 IS follows]-> (u2 IS user)
                     -[e2 IS follows]-> (u3 IS user)
                     -[e3 IS follows]-> (u1)
  WHERE u1.id < u2.id AND u2.id < u3.id  -- avoid duplicate triangles
    AND e1.is_active = 'Y'
    AND e2.is_active = 'Y'
    AND e3.is_active = 'Y'
  COLUMNS (u1.id AS v1, u2.id AS v2, u3.id AS v3)
) FETCH FIRST 1000 ROWS ONLY;
```

**Performance Characteristics**:
- Hops: 3 (circular)
- Edge joins: 3
- Vertex joins: 3 (u1 appears twice — self-join)
- Fan-out risk: **EXTREME** — 3 edge traversals without anchor
- Key optimization: The inequality `u1.id < u2.id < u3.id` eliminates duplicate triangles (6x reduction)

**Index Strategy**:
- All FK indexes on follows(src, dst) are mandatory
- The anchor inequality `u1.id < u2.id` helps but doesn't reduce fan-out at the edge level
- Consider partitioning the follows table by `src` for better partition pruning
- Composite: `CREATE INDEX idx_follows_src_dst ON follows(src, dst)` — covers both FK and enables index-only join

**Anti-patterns**:
- Without the ordering inequality, each triangle is found 6 times (all permutations)
- Without FETCH FIRST, dense communities can produce millions of triangles
- Don't run on the full graph — always constrain to a subgraph (community, region, time window)

**Real-world frequency**: **LOW** — typically batch/analytics, not real-time

---

## Pattern 4: Content Recommendation (Collaborative Filtering)

**Graph Pattern**:
```
(u1) -[e1 IS likes]-> (content) <-[e2 IS likes]- (similar_user) -[e3 IS likes]-> (recommended)
```

**SQL/PGQ**:
```sql
SELECT recommended_id, COUNT(*) AS score
FROM GRAPH_TABLE(social_graph
  MATCH (u1 IS user)     -[e1 IS likes]-> (c IS content)
                         <-[e2 IS likes]- (u2 IS user)
                          -[e3 IS likes]-> (rec IS content)
  WHERE u1.id = :user_id
    AND u1.id <> u2.id
    AND c.id <> rec.id
  COLUMNS (rec.id AS recommended_id)
)
GROUP BY recommended_id
ORDER BY score DESC
FETCH FIRST 20 ROWS ONLY;
```

**Performance Characteristics**:
- Hops: 2 (user → content → similar_user → recommended_content)
- Edge joins: 3
- Vertex joins: 4
- Fan-out risk: **VERY HIGH** — popular content has many likers, each liker has many likes
- Key challenge: intermediate result (similar_users) can be huge

**Index Strategy**:
- `CREATE INDEX idx_likes_src ON likes(src)` — u1's liked content
- `CREATE INDEX idx_likes_dst ON likes(dst)` — reverse: who liked this content
- Composite: `CREATE INDEX idx_likes_dst_src ON likes(dst, src)` — covers reverse traversal FK pair
- Consider pre-filtering: only include `similar_user` with a minimum overlap threshold

**Anti-patterns**:
- Don't compute recommendations in real-time for high-degree users — pre-compute in batch
- The GROUP BY + ORDER BY generates a sort — ensure enough PGA for sorting
- Don't recommend content the user already liked — add `NOT EXISTS` or anti-join

**Real-world frequency**: **MEDIUM** — common in recommendation engines, usually batch

---

## Pattern 5: Shortest Path Approximation (BFS-like)

**Graph Pattern**:
```
(source) -[e1]-> (hop1) -[e2]-> (hop2) ... -[eN]-> (target)
```

**SQL/PGQ**:
```sql
-- Check if target is reachable within 3 hops
SELECT CASE WHEN COUNT(*) > 0 THEN 'CONNECTED' ELSE 'NOT CONNECTED' END AS status
FROM GRAPH_TABLE(social_graph
  MATCH (s IS user) -[e1 IS follows]-> (h1 IS user)
                    -[e2 IS follows]-> (h2 IS user)
                    -[e3 IS follows]-> (t IS user)
  WHERE s.id = :source_id
    AND t.id = :target_id
    AND e1.is_active = 'Y' AND e2.is_active = 'Y' AND e3.is_active = 'Y'
  COLUMNS (1 AS found)
) FETCH FIRST 1 ROWS ONLY;
```

**Performance Characteristics**:
- Hops: N (fixed at query write time — SQL/PGQ has no variable-length paths in Oracle 23ai)
- Edge joins: N
- Vertex joins: N+1
- Fan-out risk: **EXTREME** for N>2 without early termination
- Key constraint: Oracle SQL/PGQ does not support `SHORTEST PATH` or variable-length patterns — must enumerate fixed lengths

**Index Strategy**:
- FK indexes on follows(src) and follows(dst) are **mandatory** for any multi-hop
- `FETCH FIRST 1 ROWS ONLY` is critical — we only need existence, not all paths
- The optimizer can short-circuit with FIRST ROWS optimization when indexes support nested loops
- For directed graphs, `CREATE INDEX idx_follows_src_dst ON follows(src, dst)` enables index-only traversal

**Anti-patterns**:
- Don't try to find all shortest paths — use FETCH FIRST 1
- Don't increment hop count dynamically in PL/SQL loops — write separate queries for each hop count (1, 2, 3)
- Oracle 23ai does not support `MATCH ANY SHORTEST` or `MATCH ALL SHORTEST` — these are in the SQL/PGQ spec but not yet implemented

**Real-world frequency**: **LOW** in real-time, **MEDIUM** in analytics (degrees of separation)
