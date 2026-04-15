#!/bin/bash
# Build and run fuzz targets with libFuzzer + AddressSanitizer.
# Usage: ./Tools/run-fuzzers.sh [max_time] [-j N | --workers N] [-r N | --runs N] [FuzzTarget ...]
#   max_time: seconds per target (default 300). Ignored when --runs is set.
#   -j / --workers N: parallel worker processes per target (default: ceil(logical_cpus / num_targets))
#   -r / --runs N: total executions across all workers (workers each run N/workers)
#   FuzzTarget: subset of targets to run (default: all)
# Examples:
#   ./Tools/run-fuzzers.sh 3600 -j 16 FuzzCst     # 16 workers, FuzzCst, 1 hour
#   ./Tools/run-fuzzers.sh -r 200000000 FuzzCst   # ~200M total runs, auto workers
#   ./Tools/run-fuzzers.sh 30 FuzzCst             # auto workers, 30s
#   ./Tools/run-fuzzers.sh                        # auto workers, all targets, 5 min

set -euo pipefail
cd "$(dirname "$0")/.."

# First positional arg is max_time if it looks like a number; otherwise use default
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
  MAX_TIME="$1"
  shift
else
  MAX_TIME="300"
fi

BUILD_DIR=".build/arm64-apple-macosx/debug"
MODULE_DIR="$BUILD_DIR/Modules"
LIB_OBJS=$(find "$BUILD_DIR/LogicFiles.build" -name "*.o" | tr '\n' ' ')

ALL_TARGETS=(FuzzPst FuzzAupreset FuzzCst FuzzPatchData FuzzLogicxProjectInformation FuzzLogicxMetaData FuzzLogicxDisplayState FuzzKeyedArchive)
ALL_CORPUS_DIRS=(pst aupreset cst patchdata projectinfo metadata displaystate keyedarchive)

# Parse flags and collect target names
WORKERS="auto"
RUNS=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -j|--workers)  WORKERS="$2"; shift 2 ;;
    -r|--runs)     RUNS="$2";    shift 2 ;;
    *)             POSITIONAL+=("$1"); shift ;;
  esac
done

if [ "${#POSITIONAL[@]}" -eq 0 ]; then
  TARGETS=("${ALL_TARGETS[@]}")
  CORPUS_DIRS=("${ALL_CORPUS_DIRS[@]}")
else
  TARGETS=()
  CORPUS_DIRS=()
  for requested in "${POSITIONAL[@]}"; do
    found=0
    for i in "${!ALL_TARGETS[@]}"; do
      if [ "${ALL_TARGETS[$i]}" = "$requested" ]; then
        TARGETS+=("${ALL_TARGETS[$i]}")
        CORPUS_DIRS+=("${ALL_CORPUS_DIRS[$i]}")
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      echo "Unknown target: $requested"
      echo "Valid targets: ${ALL_TARGETS[*]}"
      exit 1
    fi
  done
fi

# Resolve worker count
CPU_COUNT=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 1)
if [ "$WORKERS" = "auto" ]; then
  N_TARGETS="${#TARGETS[@]}"
  WORKERS=$(( (CPU_COUNT + N_TARGETS - 1) / N_TARGETS ))
  [ "$WORKERS" -lt 1 ] && WORKERS=1
fi

echo "=== Building library with sanitizer instrumentation ==="
# Remove cached LogicFiles .o files before the sanitizer build. SPM shares one
# .build/debug directory across all debug builds regardless of compiler flags, so
# a prior non-sanitized build leaves stale uninstrumented objects that get linked
# into the fuzzer, silently gutting coverage. Removing just the LogicFiles objects
# forces a full re-instrumentation without discarding fuzz-target build artifacts.
rm -rf "$BUILD_DIR/LogicFiles.build"
swift build -c debug -Xswiftc -sanitize=fuzzer,address --target LogicFiles

echo "=== Building fuzz targets ==="
for target in "${TARGETS[@]}"; do
  echo "  Building $target..."
  # shellcheck disable=SC2086
  swiftc -sanitize=fuzzer,address -parse-as-library \
    -I "$MODULE_DIR" \
    $LIB_OBJS \
    "Tools/$target/$target.swift" \
    -o ".build/debug/${target}Direct"
done

if [ -n "$RUNS" ]; then
  PER_WORKER=$(( RUNS / WORKERS ))
  LIMIT_DESC="~${RUNS} total runs (${PER_WORKER} per worker)"
else
  PER_WORKER=""
  LIMIT_DESC="${MAX_TIME}s"
fi

echo "=== Running ${#TARGETS[@]} target(s) x ${WORKERS} worker(s), ${LIMIT_DESC} ($CPU_COUNT logical CPUs) ==="
PIDS=()
for i in "${!TARGETS[@]}"; do
  target="${TARGETS[$i]}"
  corpus="Fuzz/Corpus/${CORPUS_DIRS[$i]}"
  for w in $(seq 0 $((WORKERS - 1))); do
    if [ "$WORKERS" -eq 1 ]; then
      log="Fuzz/${target}.log"
    else
      log="Fuzz/${target}_w${w}.log"
    fi
    echo "  Starting $target worker $w -> $log"
    if [ -n "$PER_WORKER" ]; then
      ".build/debug/${target}Direct" "$corpus" \
        -runs="$PER_WORKER" \
        -print_final_stats=1 \
        > "$log" 2>&1 &
    else
      ".build/debug/${target}Direct" "$corpus" \
        -max_total_time="$MAX_TIME" \
        -print_final_stats=1 \
        > "$log" 2>&1 &
    fi
    PIDS+=($!)
  done
done

echo "=== Waiting for all fuzzers to finish ==="
FAILED=0
PID_IDX=0
for i in "${!TARGETS[@]}"; do
  target="${TARGETS[$i]}"
  for w in $(seq 0 $((WORKERS - 1))); do
    if [ "$WORKERS" -eq 1 ]; then
      log="Fuzz/${target}.log"
    else
      log="Fuzz/${target}_w${w}.log"
    fi
    if wait "${PIDS[$PID_IDX]}"; then
      echo "  $target worker $w: OK"
    else
      echo "  $target worker $w: CRASHED (see $log)"
      FAILED=$((FAILED + 1))
    fi
    PID_IDX=$((PID_IDX + 1))
  done
done

echo ""
echo "=== Summary ==="
for i in "${!TARGETS[@]}"; do
  target="${TARGETS[$i]}"
  total_units=0
  for w in $(seq 0 $((WORKERS - 1))); do
    if [ "$WORKERS" -eq 1 ]; then
      log="Fuzz/${target}.log"
    else
      log="Fuzz/${target}_w${w}.log"
    fi
    if [ -f "$log" ]; then
      units=$(grep "stat::number_of_executed_units:" "$log" 2>/dev/null \
        | awk -F': ' '{print $2}' | tr -d ' ' || true)
      total_units=$((total_units + ${units:-0}))
    fi
  done
  if [ "$WORKERS" -eq 1 ]; then
    echo "  $target: stat::number_of_executed_units: $total_units"
  else
    echo "  $target ($WORKERS workers): stat::number_of_executed_units: $total_units"
  fi
done

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "CRASHES FOUND: $FAILED worker(s) crashed. Check crash-* files and logs."
  exit 1
else
  echo ""
  echo "No crashes found."
fi
