#!/usr/bin/env bash
# Golden-file tests. Each case captures stdout, stderr and the exit code
# and compares them with tests/expected/<name>.out.
# Run with UPDATE=1 to regenerate the expected files after a deliberate change.
set -euo pipefail
cd "$(dirname "$0")/.."

failures=0
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

check() {
  local name=$1; shift
  local expected="tests/expected/$name.out"
  local actual
  actual=$("$@" 2>&1; echo "[exit $?]") || true
  if [[ "${UPDATE:-}" == 1 ]]; then
    printf '%s\n' "$actual" > "$expected"
    echo "updated $name"
  elif diff -u "$expected" <(printf '%s\n' "$actual") > /dev/null; then
    echo "ok      $name"
  else
    echo "FAIL    $name"
    diff -u "$expected" <(printf '%s\n' "$actual") | head -20 || true
    failures=$((failures + 1))
  fi
}

# Runs the CLI into a fresh directory, then prints every output file.
# The directory name is masked so expected output is stable.
batch() {
  local out="$scratch/out"
  local rc=0
  rm -rf "$out"
  { build/ledger --date 20261031 "$@" "$out" 2>&1; echo $? > "$scratch/rc"; } \
    | sed "s#$out#OUTDIR#g"
  rc=$(cat "$scratch/rc")
  for f in exceptions.txt statements.txt accounts.new.dat events.jsonl; do
    if [[ -f "$out/$f" ]]; then echo "--- $f"; cat "$out/$f"; fi
  done
  if [[ -f "$out/events.jsonl" ]]; then
    python3 -c 'import json, sys; print("--- events parse:", sum(1 for line in open(sys.argv[1]) if json.loads(line)))' \
      "$out/events.jsonl"
  fi
  echo "--- work files left: $(find "$out" -name '.work-*' 2>/dev/null | wc -l | tr -d ' ')"
  return $rc
}

# Posts both files to the CGI program as a browser form would.
post() {
  local body
  body=$(python3 -c '
import sys, urllib.parse
read = lambda p: open(p).read().replace("\n", "\r\n")
print(urllib.parse.urlencode({"accounts": read(sys.argv[1]), "transactions": read(sys.argv[2])}), end="")
' "$1" "$2")
  printf '%s' "$body" | env REQUEST_METHOD=POST CONTENT_LENGTH=${#body} \
    LEDGER_RUN_DATE=20261031 build/ledgerweb
}

check cli-sample          batch samples/accounts.dat samples/transactions.dat
check cli-limits          batch tests/data/limits-accounts.dat tests/data/limits-transactions.dat
check cli-clean-run       batch tests/data/limits-accounts.dat tests/data/clean-transactions.dat
check cli-unsorted-master batch tests/data/unsorted-accounts.dat tests/data/clean-transactions.dat
check cli-invalid-master  batch tests/data/invalid-accounts.dat tests/data/clean-transactions.dat
check cli-missing-master  batch tests/data/does-not-exist.dat samples/transactions.dat
check cli-missing-txns    batch samples/accounts.dat tests/data/does-not-exist.dat
check cli-escaping        batch tests/data/limits-accounts.dat tests/data/escaping-transactions.dat
check cli-help            build/ledger --help
check cli-missing-args    build/ledger samples/accounts.dat
check cli-bad-date        build/ledger --date 20261340 a b c

check web-form            env REQUEST_METHOD=GET LEDGER_SAMPLES=samples build/ledgerweb
check web-post            post samples/accounts.dat samples/transactions.dat
check web-too-large       env REQUEST_METHOD=POST CONTENT_LENGTH=999999 LEDGER_SAMPLES=samples build/ledgerweb

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
