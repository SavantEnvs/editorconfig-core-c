#!/usr/bin/env bash
# mayhem/build.sh — builds the sanitized libeditorconfig + fuzz harnesses, and the normal-flags test build.
# Re-runnable and offline (libpcre2-dev is baked into the image by mayhem/Dockerfile).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs come from the ENVIRONMENT (overridable), with sane defaults — no if-statements,
# just parameter-expansion fallbacks. Default sanitizers are the base's ASan+UBSan (halting); override
# per build via the Dockerfile's `--build-arg SANITIZER_FLAGS="..."`.
# NB: SANITIZER_FLAGS uses `=` (no colon) on purpose — `=` only fills when the var is UNSET, so an
# explicit EMPTY value (`--build-arg SANITIZER_FLAGS=`) is honored and builds with NO sanitizers
# (useful when you want the program's natural crash / full backtrace, not an ASan report). The other
# knobs use `:=` (default on empty too). MAYHEM_JOBS sets build parallelism (falls back to nproc).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS carries DWARF debug info INDEPENDENTLY of the sanitizer off-switch (so an empty
# SANITIZER_FLAGS still yields DWARF symbols). DWARF MUST be < 4 (Mayhem triage can't read >=4); clang-19's
# plain `-g` emits DWARF-5, so `-gdwarf-3` is explicit. Apply $DEBUG_FLAGS to the fuzz/harness/standalone
# builds (NOT the test/oracle build). Rust/Go carry the same intent via their language flags below.
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3}"
: "${GO_DEBUG_FLAGS:=-gcflags=all=-N -l}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
# COVERAGE_FLAGS: empty by default → no effect on the normal oracle build. Set it via the Dockerfile's
# `--build-arg COVERAGE_FLAGS="-fprofile-instr-generate -fcoverage-mapping"` to instrument the TEST
# build for source-coverage measurement (how much of the project the test suite actually exercises —
# a quality signal for the oracle; complements the anti-reward-hack sabotage check). APPEND it to the
# test build's compile+link flags in step 3 (NOT the fuzz build); after `test.sh` runs, merge with
# `llvm-profdata` and report with `llvm-cov`. Empty value is honored (`=`, not `:=`).
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS RUST_DEBUG_FLAGS GO_DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# Build dirs live under mayhem/ so mayhem/.gitignore (additive) covers them for `git clean -ffdX`.
FZ="$SRC/mayhem/build-fuzz"
TS="$SRC/mayhem/build-test"

# 1) Project itself, sanitized + DWARF 3 (static lib + the CLI).
cmake -S . -B "$FZ" -DCMAKE_BUILD_TYPE=None -DCMAKE_C_COMPILER="$CC" \
      -DCMAKE_C_FLAGS="-O1 $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link" \
      -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS" >/dev/null
cmake --build "$FZ" -j"$MAYHEM_JOBS" --target editorconfig_static editorconfig_bin

# 2) Harnesses: libFuzzer binary + standalone (run-once) reproducer each. LSan off at build time.
INC="-I$SRC/include -I$SRC/src/lib -I$FZ/src/auto"
LIB="$FZ/lib/libeditorconfig_static.a -lpcre2-8"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$FZ/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$FZ/standalone_main.o"
for h in fuzz_ec_glob fuzz_editorconfig_parse; do
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE $INC "$SRC/mayhem/$h.c" "$FZ/lsan_off.o" $LIB -o "/mayhem/$h"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $INC "$SRC/mayhem/$h.c" "$FZ/standalone_main.o" "$FZ/lsan_off.o" $LIB -o "/mayhem/$h-standalone"
done

# 3) Test build with the project's normal flags: the CLI plus a known-answer ec_glob probe.
cmake -S . -B "$TS" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" \
      -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_EXE_LINKER_FLAGS="$COVERAGE_FLAGS" >/dev/null
cmake --build "$TS" -j"$MAYHEM_JOBS" --target editorconfig_static editorconfig_bin
$CC -O2 $COVERAGE_FLAGS -I"$SRC/include" -I"$SRC/src/lib" -I"$TS/src/auto" "$SRC/mayhem/ec_kat.c" \
    "$TS/lib/libeditorconfig_static.a" -lpcre2-8 -o "$TS/ec_kat"
