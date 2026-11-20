---
description: Review the current Laravel changes for authorization, injection, caching, N+1 and Blade escaping bugs
argument-hint: [path or branch, or blank for the working diff]
allowed-tools: Read, Grep, Glob, Bash, Task, Skill
---

Review: **$ARGUMENTS** (blank = `git diff` plus staged changes)

Delegate to `laravel-reviewer`. Give it the diff scope and anything you already know about the project's conventions so it doesn't rediscover them.

It reviews, in priority order: authorization (per object, not just per role), mass assignment and SQL injection, `env()`/config-cache and deploy correctness, slim-skeleton mistakes, data correctness (casts, indexes, transactions), caching and its invalidation, N+1 and unbounded queries, Blade escaping and form completeness, then language-level quality.

When it reports back:

- **Verify each finding yourself before acting on it** — read the code it cites. A confidently wrong finding costs more than a missed one.
- Fix what is confirmed, in severity order.
- If you disagree with a finding, say why in the report rather than silently dropping it.

## Report

The findings that survived verification, what you fixed, what you left and why. If nothing is wrong, say so plainly — do not manufacture findings.
