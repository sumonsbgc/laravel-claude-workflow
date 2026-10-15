#!/usr/bin/env bash
# 003 — behaviour: per-user list + guest redirect over HTTP; authorization via a hidden feature test
J="$(mktemp)"; trap 'rm -f "$J"' EXIT
curl -fsS -c "$J" -b "$J" -o /dev/null "$BASE_URL/__eval/login/1" || { echo "eval login failed"; exit 1; }
H="$(curl -fsS -b "$J" "$BASE_URL/admin/news")" || { echo "/admin/news did not render for user 1"; exit 1; }
printf '%s' "$H" | grep -q "Website redesign" || { echo "user 1 does not see their news"; exit 1; }
printf '%s' "$H" | grep -q "Someone else" && { echo "user 1 sees another user's news"; exit 1; }
printf '%s' "$H" | grep -q "2 news items" || { echo "heading doesn't show '2 news items' (NewsLabel)"; exit 1; }
read -r CODE URL <<<"$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$BASE_URL/admin/news")"
case "$CODE" in 301|302|303|307|308) ;; *) echo "guest was not redirected (HTTP $CODE)"; exit 1 ;; esac
[[ "$URL" =~ ^https?://[^/]+/?$ ]] || { echo "guest redirect goes to '$URL', not /"; exit 1; }
cp "$EVALS/hidden/AdminNewsHiddenTest.php" tests/Feature/EvalHiddenAdminNewsTest.php
OUT="$(php artisan test tests/Feature/EvalHiddenAdminNewsTest.php 2>&1)"; RC=$?
rm -f tests/Feature/EvalHiddenAdminNewsTest.php
[ "$RC" = 0 ] || { echo "authorization test failed: $(printf '%s' "$OUT" | grep -E 'FAIL|Failed asserting|Expected' | head -3 | tr '\n' ' ')"; exit 1; }
