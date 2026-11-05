#!/usr/bin/env bash
# Golden-file tests. Each case captures stdout, stderr and the exit code
# and compares them with tests/expected/<name>.out.
# Run with UPDATE=1 to regenerate the expected files after a deliberate change.
set -euo pipefail
cd "$(dirname "$0")/.."

failures=0

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

cli=build/amortise
web=build/amortweb
api=build/amortapi

check cli-standard          $cli 250000 11.75 240
check cli-zero-rate         $cli 100 0 3
check cli-csv               $cli --csv 1000 12 3
check cli-interest-only     $cli 999999999.99 100 600
check cli-help              $cli --help
check cli-missing-args      $cli 1000 12
check cli-bad-principal     $cli abc 12 3
check cli-too-many-decimals $cli 100.555 12 3
check cli-negative-rate     $cli 1000 -1 3
check cli-term-too-long     $cli 1000 12 601
check cli-fractional-term   $cli 1000 12 3.5
check cli-payment-too-small $cli 1 0 600

check web-empty-form        env QUERY_STRING= $web
check web-schedule          env "QUERY_STRING=principal=1000&rate=12&term=3" $web
check web-invalid-term      env "QUERY_STRING=principal=1000&rate=12&term=0" $web
check web-no-echo-of-markup env "QUERY_STRING=principal=%3Cscript%3E&rate=12&term=3" $web
check web-overlong-value    env "QUERY_STRING=principal=1000000000000000000001&rate=1&term=1" $web

check api-schedule          env REQUEST_METHOD=GET "QUERY_STRING=principal=1000&rate=12&term=3" $api
check api-zero-rate         env REQUEST_METHOD=GET "QUERY_STRING=principal=100&rate=0&term=3" $api
check api-no-parameters     env REQUEST_METHOD=GET QUERY_STRING= $api
check api-invalid-principal env REQUEST_METHOD=GET "QUERY_STRING=principal=%3Cscript%3E&rate=12&term=3" $api
check api-invalid-rate      env REQUEST_METHOD=GET "QUERY_STRING=principal=1000&rate=12.00001&term=3" $api
check api-invalid-term      env REQUEST_METHOD=GET "QUERY_STRING=principal=1000&rate=12&term=601" $api
check api-payment-too-small env REQUEST_METHOD=GET "QUERY_STRING=principal=1&rate=0&term=600" $api
check api-post              env REQUEST_METHOD=POST "QUERY_STRING=principal=1000&rate=12&term=3" $api
# The largest possible response: 600 rows of the widest amounts.
check api-largest           sh -c 'REQUEST_METHOD=GET QUERY_STRING="principal=999999999.99&rate=100&term=600" '$api' | tail -1 | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d[\"schedule\"]), d[\"totalPaid\"], d[\"schedule\"][-1])"'

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
