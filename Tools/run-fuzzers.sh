#!/bin/bash
# Build and run all fuzz targets with libFuzzer + AddressSanitizer.
# Usage: ./Tools/run-fuzzers.sh [max_total_time_seconds]
#   Default: 300 seconds (5 minutes) per target.

set -euo pipefail
cd "$(dirname "$0")/.."

MAX_TIME="${1:-300}"
BUILD_DIR=".build/arm64-apple-macosx/debug"
MODULE_DIR="$BUILD_DIR/Modules"
LIB_OBJS=$(find "$BUILD_DIR/LogicFiles.build" -name "*.o" | tr '\n' ' ')

TARGETS=(FuzzPst FuzzAupreset FuzzCst FuzzPatchData FuzzLogicxProjectInformation FuzzLogicxMetaData FuzzLogicxDisplayState FuzzKeyedArchive)
CORPUS_DIRS=(pst aupreset cst patchdata projectinfo metadata displaystate keyedarchive)

echo "=== Building library with sanitizer instrumentation ==="
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

echo "=== Running fuzz targets (${MAX_TIME}s each, in parallel) ==="
PIDS=()
for i in "${!TARGETS[@]}"; do
  target="${TARGETS[$i]}"
  corpus="Fuzz/Corpus/${CORPUS_DIRS[$i]}"
  log="Fuzz/${target}.log"
  echo "  Starting $target -> $log"
  ".build/debug/${target}Direct" "$corpus" \
    -max_total_time="$MAX_TIME" \
    -print_final_stats=1 \
    > "$log" 2>&1 &
  PIDS+=($!)
done

echo "=== Waiting for all fuzzers to finish ==="
FAILED=0
for i in "${!TARGETS[@]}"; do
  target="${TARGETS[$i]}"
  if wait "${PIDS[$i]}"; then
    echo "  $target: OK"
  else
    echo "  $target: CRASHED (see Fuzz/${target}.log)"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "=== Summary ==="
for i in "${!TARGETS[@]}"; do
  target="${TARGETS[$i]}"
  log="Fuzz/${target}.log"
  if [ -f "$log" ]; then
    done_line=$(grep "^#.*DONE" "$log" 2>/dev/null || echo "N/A")
    stats_line=$(grep "stat::number_of_executed_units:" "$log" 2>/dev/null || echo "N/A")
    echo "  $target: $stats_line"
  fi
done

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "CRASHES FOUND: $FAILED target(s) crashed. Check crash-* files and logs."
  exit 1
else
  echo ""
  echo "No crashes found."
fi
