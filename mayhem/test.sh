#!/usr/bin/env bash
#
# xlrd/mayhem/test.sh — behavioral oracle for python-excel/xlrd.
#
# It RUNS the real reader (via the /mayhem/run-cli launcher built by mayhem/build.sh) over the
# bundled tests/samples/profiles.xls fixture and ASSERTS the decoded values (known-answer test):
# BIFF version, sheet names/count, sheet dimensions, and several cell values. This exercises the
# SAME pipeline the fuzzer drives — file read -> BIFF parse -> sheet/cell decode — so a no-op/
# neutered program (no output, or wrong output) FAILS here. It never builds; it only runs the
# pre-built launcher.
#
# Anti-reward-hack note: run-cli lives at /mayhem (a NON-system path), so the verify-repo sabotage
# neuter (_exit(0) on non-system exes) trips it -> empty output -> assertions fail -> detected.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

CLI="$SRC/run-cli"
XLS="$SRC/tests/samples/profiles.xls"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf "CTRF {\"results\":{\"tool\":{\"name\":\"%s\"},\"summary\":{\"tests\":%d,\"passed\":%d,\"failed\":%d,\"pending\":%d,\"skipped\":%d,\"other\":%d}}}\n" \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PASS=0; FAIL=0
check() { # check <name> <condition-rc>
  if [ "$2" -eq 0 ]; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi
}

if [ ! -x "$CLI" ]; then
  echo "missing $CLI — run mayhem/build.sh first" >&2
  emit_ctrf "xlrd-knownanswer" 0 1 0; exit 2
fi
if [ ! -f "$XLS" ]; then
  echo "missing $XLS" >&2
  emit_ctrf "xlrd-knownanswer" 0 1 0; exit 2
fi

echo "=== reading profiles.xls (workbook dump to stdout) ==="
OUT="$("$CLI" "$XLS" 2>/dev/null)"
echo "$OUT"

# Known answers for the bundled tests/samples/profiles.xls fixture (BIFF8 / Excel 97-2003).
grep -q "^BIFF=80$"                                                                     <<<"$OUT"; check "BIFF version 80" $?
grep -q "^NSHEETS=5$"                                                                   <<<"$OUT"; check "5 sheets" $?
grep -q "^SHEETNAMES=PROFILEDEF,AXISDEF,TRAVERSALCHAINAGE,AXISDATUMLEVELS,PROFILELEVELS$" <<<"$OUT"; check "sheet names decoded" $?
grep -q "^SHEET0NAME=PROFILEDEF$"                                                       <<<"$OUT"; check "first sheet name" $?
grep -q "^NROWS=15$"                                                                    <<<"$OUT"; check "row count" $?
grep -q "^NCOLS=13$"                                                                    <<<"$OUT"; check "col count" $?
grep -q "^A1=PROFIL$"                                                                   <<<"$OUT"; check "cell A1 decoded" $?
grep -q "^B1=a$"                                                                        <<<"$OUT"; check "cell B1 decoded" $?
grep -q "^A2=P8.2$"                                                                     <<<"$OUT"; check "cell A2 decoded" $?

emit_ctrf "xlrd-knownanswer" "$PASS" "$FAIL" 0
