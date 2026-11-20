---
description: Run performance and accessibility audits over the app (or a path)
argument-hint: [path or route, or blank for the whole app]
allowed-tools: Read, Grep, Glob, Bash, Task, TodoWrite, Skill
---

Audit: **$ARGUMENTS** (blank = the highest-traffic routes and every form)

Run both auditors **in parallel** — they read different things and don't conflict:

- `laravel-perf-auditor` — N+1s, unbounded reads, missing indexes, work in the request that belongs in a queue, caching gaps, production config, asset weight.
- `blade-a11y-auditor` — semantics, keyboard operation, labels and errors, focus management in Alpine widgets, contrast, motion.

Then merge their reports yourself:

1. **Verify before you believe.** Read the code behind each finding. For performance claims, prefer a measured number — a query count from `DB::enableQueryLog()` or `Model::preventLazyLoading()` in local — over an assertion.
2. **Rank by impact**, not by which agent found it. An N+1 on the public homepage outranks a missing `alt` on an admin icon; a form nobody can complete with a keyboard outranks both.
3. **Deduplicate.** Both agents will notice the same view for different reasons.

Fix only what the user asked you to fix. If they asked only for an audit, report and stop.

## Report

One ranked list. Each item: where, what it costs and to whom, the fix, and the risk of that fix. Separate "measured" from "inferred". Say plainly if a whole category is already in good shape.
