#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
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
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TS="$SRC/mayhem/build-test"
EC="$TS/bin/editorconfig"
KAT="$TS/ec_kat"
for b in "$EC" "$KAT"; do
  [ -x "$b" ] || { echo "missing $b — mayhem/build.sh should have built it" >&2; emit_ctrf "editorconfig-kat" 0 1 0; exit 1; }
done

passed=0; failed=0
check() {  # check <name> <expected> <actual>
  if [ "$2" == "$3" ]; then passed=$((passed+1)); echo "ok   $1"
  else failed=$((failed+1)); echo "FAIL $1: expected [$2] got [$3]"; fi
}

# Per-case known answers from the ec_glob() probe (0 = match, 1 = no match).
katout="$("$KAT" 2>&1)"
while read -r n want got pat str; do
  [[ "$n" =~ ^[0-9]+$ ]] || continue
  check "ec_glob '$pat' ~ '$str'" "$want" "$got"
done <<<"$katout"
check "ec_glob case count" "19" "$(grep -c '^[0-9]' <<<"$katout")"
check "ec_glob probe summary" "ec_glob kat mismatches=0" "$(tail -n1 <<<"$katout")"

# End-to-end through the CLI: a known .editorconfig tree -> exact property output.
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/proj/sub"
cat > "$W/proj/.editorconfig" <<'CFG'
root = true

[*]
indent_style = space
indent_size = 4
end_of_line = lf

[*.py]
indent_size = 2
charset = utf-8

[Makefile]
indent_style = tab

[{a,b}.txt]
trim_trailing_whitespace = true
CFG
cat > "$W/proj/sub/.editorconfig" <<'CFG'
[*.py]
indent_size = 8
CFG
srt() { sort; }
check "cli *.py"            $'charset=utf-8\nend_of_line=lf\nindent_size=2\nindent_style=space\ntab_width=2' "$("$EC" "$W/proj/x.py" | srt)"
check "cli sub/*.py"        $'charset=utf-8\nend_of_line=lf\nindent_size=8\nindent_style=space\ntab_width=8' "$("$EC" "$W/proj/sub/x.py" | srt)"
check "cli Makefile"        $'end_of_line=lf\nindent_size=4\nindent_style=tab\ntab_width=4' "$("$EC" "$W/proj/Makefile" | srt)"
check "cli b.txt"           $'end_of_line=lf\nindent_size=4\nindent_style=space\ntab_width=4\ntrim_trailing_whitespace=true' "$("$EC" "$W/proj/b.txt" | srt)"
check "cli c.txt"           $'end_of_line=lf\nindent_size=4\nindent_style=space\ntab_width=4' "$("$EC" "$W/proj/c.txt" | srt)"
check "cli --version"       "yes" "$("$EC" --version | grep -q 'EditorConfig' && echo yes || echo no)"

emit_ctrf "editorconfig-kat" "$passed" "$failed" 0
