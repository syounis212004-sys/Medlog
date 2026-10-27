#!/usr/bin/env bash
# Runs every test of app/test (the ones that need only the repository). Run from the app folder.
# Usage: tool/run_tests.sh [file.dart ...]
set -u
cd "$(dirname "$0")/.."
export PATH="${FLUTTER_ROOT:+$FLUTTER_ROOT/bin:}$PATH"
mkdir -p test_output
if [ $# -gt 0 ]; then FILES="$@"; else FILES=$(ls test/*_test.dart); fi
: > test_output/summary.txt
fail=0
for f in $FILES; do
  out=$(timeout 1500 flutter test --reporter expanded "$f" 2>&1)
  code=$?
  line=$(echo "$out" | grep -E 'All tests passed|Some tests failed' | tail -1)
  [ $code -eq 0 ] && line="${line:-passed (exit 0)}"
  echo "== $f: ${line:-NO RESULT (exit $code)}" | tee -a test_output/summary.txt
  if [ $code -ne 0 ]; then
    fail=1
    [ -z "$line" ] && echo "$out" | tail -15 | tee -a test_output/summary.txt
    echo "$out" | grep -E '\[E\]|Expected|Actual|Exception|Error' | sort -u | head -12 | tee -a test_output/summary.txt
  fi
done
echo "FINISHED fail=$fail" | tee -a test_output/summary.txt
exit $fail
