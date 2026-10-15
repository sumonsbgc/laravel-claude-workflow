#!/usr/bin/env bash
# 002 — behaviour: a hidden Pest test (never shown to the agent) against the helper
[ -f app/Support/NewsLabel.php ] || { echo "app/Support/NewsLabel.php missing"; exit 1; }
cp "$EVALS/hidden/NewsLabelHiddenTest.php" tests/Unit/EvalHiddenNewsLabelTest.php
OUT="$(php artisan test tests/Unit/EvalHiddenNewsLabelTest.php 2>&1)"; RC=$?
rm -f tests/Unit/EvalHiddenNewsLabelTest.php
[ "$RC" = 0 ] || { echo "hidden test failed: $(printf '%s' "$OUT" | grep -E 'FAIL|Failed asserting|Expected' | head -3 | tr '\n' ' ')"; exit 1; }
