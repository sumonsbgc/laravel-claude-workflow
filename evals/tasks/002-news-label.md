---
id: 002
title: News count label helper
status: todo
depends:
size: small
---

## Goal
One helper turns a number of news items into a label so views never hand-roll pluralisation.

## Acceptance
- [ ] [test] App\Support\NewsLabel::count(0) === "No news"
- [ ] [test] App\Support\NewsLabel::count(1) === "1 news item"
- [ ] [test] App\Support\NewsLabel::count(3) === "3 news items"

## Notes
A final class with a static `count(int $n): string` method in app/Support/NewsLabel.php. Pest is installed. Out of scope: translations.
