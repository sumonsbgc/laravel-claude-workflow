#!/usr/bin/env bash
# 001 — behaviour: the home page (main layout) renders a <footer> that links home
HTML="$(curl -fsS "$BASE_URL/")" || { echo "home page did not render"; exit 1; }
FOOT="$(printf '%s' "$HTML" | tr '\n' ' ' | grep -oE '<footer[^>]*>.*</footer>')"
[ -n "$FOOT" ] || { echo "no <footer> on /"; exit 1; }
printf '%s' "$FOOT" | grep -qE "href=\"($BASE_URL)?/?\"" || { echo "footer has no link to /"; exit 1; }
