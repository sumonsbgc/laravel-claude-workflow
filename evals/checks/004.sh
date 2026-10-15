#!/usr/bin/env bash
# 004 — behaviour: case-insensitive URL search with an empty state and a GET form
J="$(mktemp)"; trap 'rm -f "$J"' EXIT
curl -fsS -c "$J" -b "$J" -o /dev/null "$BASE_URL/__eval/login/1" || { echo "eval login failed"; exit 1; }
H="$(curl -fsS -b "$J" "$BASE_URL/admin/news?q=WEB")" || { echo "/admin/news?q= did not render"; exit 1; }
printf '%s' "$H" | grep -q "Website redesign" || { echo "q=WEB does not match 'Website redesign'"; exit 1; }
printf '%s' "$H" | grep -q "Mobile app" && { echo "q=WEB still shows 'Mobile app'"; exit 1; }
H="$(curl -fsS -b "$J" "$BASE_URL/admin/news?q=zzz")"
printf '%s' "$H" | grep -q "No news match" || { echo "no empty-result message"; exit 1; }
FORM="$(printf '%s' "$H" | tr '\n' ' ' | grep -oE '<form[^>]*>' | head -1)"
[ -n "$FORM" ] || { echo "no search <form>"; exit 1; }
printf '%s' "$FORM" | grep -qiE 'method="post"' && { echo "search form posts instead of GET"; exit 1; }
true
