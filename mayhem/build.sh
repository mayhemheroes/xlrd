#!/usr/bin/env bash
#
# xlrd/mayhem/build.sh — build the Atheris fuzz target for python-excel/xlrd.
#
# This is a PYTHON (Atheris/libFuzzer) project, so the "build" is:
#   1) install xlrd + atheris, OFFLINE, from the wheelhouse the Dockerfile baked into
#      /opt/toolchains/python/wheelhouse (air-gapped, re-runnable — SPEC §6.5);
#   2) compile tiny ELF launchers (launcher.c) so the Mayhem target `cmd` is a native executable
#      (Mayhem rejects script targets; fuzz-smoke checks the ELF magic). Each launcher exec's
#      `python3 <script> "$@"`, forwarding libFuzzer flags to Atheris:
#        - /mayhem/fuzz_open_workbook             : the Mayhem libFuzzer target (Atheris iterates).
#        - /mayhem/fuzz_open_workbook.pkg         : same harness, the OSS-Fuzz `.pkg` target preserved
#                                                   for parity with the original integration.
#        - /mayhem/fuzz_open_workbook-standalone  : run-once reproducer (Atheris replays one file arg).
#        - /mayhem/run-cli                        : the oracle runner mayhem/test.sh drives (open_xls.py).
#
# NOTE on sanitizers: the fuzzed code is Python; coverage/instrumentation come from Atheris
# (atheris.instrument_imports), not from clang $SANITIZER_FLAGS — those apply to native C/C++ code,
# of which this project has none. We still thread $DEBUG_FLAGS into the launcher compile so the
# spec's debug-info contract (DWARF < 4) holds on every emitted ELF.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) so an explicit empty --build-arg SANITIZER_FLAGS= builds without sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS: explicit DWARF-3 so Mayhem triage can read symbols (clang-19's plain -g emits DWARF-5).
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${SRC:=/mayhem}"
: "${WHEELHOUSE:=/opt/toolchains/python/wheelhouse}"
export SANITIZER_FLAGS DEBUG_FLAGS CC SRC WHEELHOUSE
OUT=/mayhem

cd "$SRC"

# 1) Python deps — OFFLINE from the baked wheelhouse (idempotent; "already satisfied" on re-run).
# atheris is the fuzzing engine; setuptools/wheel are xlrd's build backend, needed to install the
# xlrd source offline with build isolation disabled.
PIP="python3 -m pip install --user --break-system-packages"
if [ -d "$WHEELHOUSE" ] && [ -n "$(ls -A "$WHEELHOUSE" 2>/dev/null)" ]; then
  $PIP --no-index --find-links "$WHEELHOUSE" atheris setuptools wheel
  $PIP --no-index --find-links "$WHEELHOUSE" --no-build-isolation .
else
  $PIP atheris setuptools wheel
  $PIP --no-build-isolation .
fi

# Sanity: the harnessed module must import.
python3 -c "import atheris, xlrd, xlrd.compdoc" \
  || { echo "FATAL: xlrd failed to import" >&2; exit 1; }

# 2) Native ELF launchers (built WITHOUT sanitizers, WITH DWARF-3 debug info).
"$CC" $DEBUG_FLAGS -O1 \
    -DHARNESS_PATH="\"$SRC/mayhem/fuzz_open_workbook.py\"" \
    -o "$OUT/fuzz_open_workbook" "$SRC/mayhem/launcher.c"


# Standalone run-once reproducer: same binary (Atheris replays a single file argument).
cp -f "$OUT/fuzz_open_workbook" "$OUT/fuzz_open_workbook-standalone"

# CLI runner for the test oracle: exec's open_xls.py (a NON-system path, so the sabotage neuter trips it).
"$CC" $DEBUG_FLAGS -O1 \
    -DHARNESS_PATH="\"$SRC/mayhem/open_xls.py\"" \
    -o "$OUT/run-cli" "$SRC/mayhem/launcher.c"

echo "build.sh complete:"
ls -la "$OUT/fuzz_open_workbook" \
       "$OUT/fuzz_open_workbook-standalone" "$OUT/run-cli"
