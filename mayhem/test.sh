#!/usr/bin/env bash
#
# mayhem/test.sh — RUN (never compile) the binaries mayhem/build.sh produced in build-tests/:
# the project's own cutest unit suite (hrg/regex/string/token/voice_select/wave/lex/lts/nums —
# real assertions over lexicon lookups, letter-to-sound rules, number expansion, tokenization,
# HRG relations and wave I/O) plus a known-answer probe through the clean, dynamically-linked
# `t2p` CLI.
#
# Deliberately does NOT drive this through automake's own `make check` / TEST_LOG driver:
# that judges each test PROGRAM only by its exit code, which is exactly the "exit-code-only test
# RUNNER" trap (see PORTING field notes §4) — a process that is killed/neutered before it prints
# anything still exits 0 and a bare exit-code runner reports it as a pass. Instead this script
# invokes every binary itself and asserts the literal PASS marker text cutest.h prints on a truly
# clean run ("SUCCESS: All unit tests have passed.") is present in stdout, and separately asserts
# t2p's exact phoneme output for a fixed sentence. A neutered/no-op'd binary produces NO stdout at
# all (it never reaches its own print statements), so both forms of assertion correctly FAIL —
# this is what makes the oracle behavioral rather than reward-hackable.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
SRC="${SRC:-/mayhem}"
cd "$SRC"

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

PASS=0
FAIL=0

# cutest.h's own success marker (unittests/cutest.h): printed only after EVERY unit test in the
# binary genuinely ran and passed; a real failure prints a "FAILED: N of M..." line instead, and a
# sabotaged/neutered process prints nothing at all.
MARKER="SUCCESS: All unit tests have passed."

UNIT_TESTS=(
  unittests/hrg_test
  unittests/regex_test
  unittests/string_test
  unittests/token_test
  unittests/voice_select
  unittests/wave_test
  unittests/lex_test
  unittests/lts_test
  unittests/nums_test
)

for t in "${UNIT_TESTS[@]}"; do
  bin="$SRC/build-tests/$t"
  if [ ! -x "$bin" ]; then
    echo "FAIL: $t — binary missing (build-tests/$t); mayhem/build.sh must build it" >&2
    FAIL=$((FAIL + 1))
    continue
  fi
  # Several of these tests were compiled with a fixture path baked in RELATIVE to top_srcdir
  # (e.g. -DTEST_FILE="../unittests/data.one", -DVOICE_LIST_DIR="../voices" — top_srcdir is ".."
  # for this out-of-tree VPATH build), so they must run with build-tests/ as cwd, exactly like
  # automake's own test driver invokes them — from anywhere else they SIGSEGV on the bad path.
  out="$(cd "$SRC/build-tests" && "./$t" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && grep -qF "$MARKER" <<<"$out"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $t (rc=$rc, marker present: $(grep -qF "$MARKER" <<<"$out" && echo yes || echo no))" >&2
    tail -5 <<<"$out" >&2
    FAIL=$((FAIL + 1))
  fi
done

# Known-answer probe: t2p (clean, no sanitizer, dynamically linked) converts a fixed English
# sentence to phonemes via the exact upstream US-English text analysis + CMU lexicon front end.
# The expected string was captured from an unmodified build of this same tree.
T2P="$SRC/build-tests/t2p"
EXPECTED="pau hh ax l ow1 w er1 l d dh ih1 s ih1 z ax t eh1 s t pau "
if [ -x "$T2P" ]; then
  actual="$("$T2P" "hello world this is a test" 2>/dev/null)"
  if [ "$actual" = "$EXPECTED" ]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: t2p KAT probe — got [$actual] want [$EXPECTED]" >&2
    FAIL=$((FAIL + 1))
  fi
else
  echo "FAIL: t2p KAT probe — binary missing (build-tests/t2p)" >&2
  FAIL=$((FAIL + 1))
fi

emit_ctrf "mimic1-cutest+kat" "$PASS" "$FAIL"
