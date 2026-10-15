---
id: 003
title: Admin news list with delete
status: todo
depends: 002
size: large
---

## Goal
Signed-in users manage their own news at /admin/news: they see only their items and can delete one. This is the first mutation in the app, so it sets the authorization pattern.

## Acceptance
- [ ] [review] GET /admin/news lists only the signed-in user's news, heading uses NewsLabel::count (e.g. "2 news items")
- [ ] [test] DELETE /admin/news/{news} on another user's item returns 403 and deletes nothing
- [ ] [test] DELETE /admin/news/{news} on the user's own item deletes it and redirects to /admin/news
- [ ] [browser] Guests requesting /admin/news are redirected to "/"

## Notes
There is no login screen: redirect guests to the home route. Authorization goes in a NewsPolicy. Out of scope: create/edit.
