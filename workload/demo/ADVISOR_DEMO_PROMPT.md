# Demo Prompt

Copy and paste this into your MCP client to start the demo:

---

I have a financial fraud detection scenario. My company has relational tables with customer accounts, merchants, devices, and money transfers between accounts.

Today we detect fraud with complex SQL self-joins and recursive CTEs. They're slow and hard to maintain. I want to evaluate if a property graph would work better.

Can you:
1. First, confirm this is not a production database
2. Assess whether a graph model makes sense for fraud detection
3. Design the graph — tell me what vertex and edge tables to create, and why
4. Build it and populate it with realistic test data
5. Show me what queries the graph can answer (fraud rings, shared devices, suspicious patterns)
6. Then analyze the workload and tell me what I should optimize BEFORE going to production
7. Create the indexes you recommend and SHOW ME the execution plan changing
8. Scale the data to 10X and verify everything still works
9. Give me a final report I can present to my team

Read `workload/demo/00_demo_script.sql` as your guide. Explain every decision.
