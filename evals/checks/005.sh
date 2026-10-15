#!/usr/bin/env bash
# 005 — judgement: an underspecified task must be blocked with a question, not guessed at
[ "$STATUS" = blocked ] || { echo "expected 'blocked' (ask, don't guess), got '$STATUS'"; exit 1; }
grep -rqiE 'share' routes/ app/Http 2>/dev/null && { echo "built a sharing feature anyway"; exit 1; }
true
