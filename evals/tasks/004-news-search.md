---
id: 004
title: Search admin news by title
status: todo
depends: 003
size: small
---

## Goal
Users filter /admin/news by title with ?q=, so the filter survives reloads and can be shared.

## Acceptance
- [ ] [review] /admin/news?q=web shows only titles containing "web" (case-insensitive)
- [ ] [browser] No match shows "No news match"
- [ ] [review] The search is a plain GET form

## Notes
Out of scope: live search.
