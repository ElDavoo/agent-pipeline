#!/usr/bin/env bash
#
# The checks an agent must pass before its work is worth pushing — this repository's lint, its
# tests, whatever else CI would refuse the branch for.
#
# REPLACE THE BODY. What ships here succeeds and does nothing, so the pipeline runs end to end
# before you have configured anything.
#
# This is a script and not a composite action on purpose, and the reason decides it: the agent
# is told to run these itself, mid-turn, before it finishes. A composite action cannot be
# invoked from inside a prompt. A script is the only form both the workflow and the agent can
# reach, which is what stops them drifting into two different definitions of "passing" — the
# failure where CI rejects a branch for a gate the agent was never able to run.
#
# Contract:
#   - exit 0 if everything passed, non-zero otherwise
#   - print enough on failure to diagnose from, on stdout or stderr
#   - be runnable from a clean checkout after project-setup has run, and from the agent's
#     working tree mid-change
#   - be cheap. It runs on every fix round, and once more inside each of them.
#
# Put the *fast* gates here — the ones worth failing before a push. Slow legs (an emulator
# matrix, a full release build) belong in CI, where the fix loop picks their failures up from
# the logs.

set -uo pipefail

failed=0

# Runs one gate, keeps going after a failure, and reports all of them rather than only the
# first. An agent that is shown one failure at a time spends one round per gate.
gate() {
  local name=$1; shift
  printf '\n=== %s ===\n' "$name"
  if "$@"; then
    printf '%s: passed\n' "$name"
  else
    printf '%s: FAILED\n' "$name"
    failed=1
  fi
}

# ------------------------------------------------------------------------------------------
# Replace these with your own. Examples:
#
#   gate lint    npm run lint
#   gate types   npx tsc --noEmit
#   gate tests   npm test
#
#   gate ruff    ruff check .
#   gate mypy    mypy src
#   gate pytest  pytest -q
#
#   gate vet     go vet ./...
#   gate tests   go test ./...
#
#   gate lint    ./gradlew --no-daemon lintDebug
#   gate tests   ./gradlew --no-daemon testDebugUnitTest
# ------------------------------------------------------------------------------------------

gate 'no gates configured' true

if [ "$failed" -ne 0 ]; then
  printf '\nOne or more gates failed.\n'
  exit 1
fi

printf '\nAll gates passed.\n'
