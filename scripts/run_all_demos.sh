#!/usr/bin/env bash
# scripts/run_all_demos.sh
#
# Run all demonstrations in sequence inside the container.
# Produces output in /workspace/{valgrind,perf}_reports/ and prints
# bench comparisons to stdout.
#
# Usage (from host):
#   docker build -t profdemo .
#   docker run --rm --privileged profdemo bash /workspace/scripts/run_all_demos.sh
#
# --privileged is needed for perf_event_paranoid override.

set -euo pipefail

echo "========================================================"
echo " profdemo: C Profiling and Debugging Demonstration"
echo "========================================================"

# Allow perf to capture kernel events
if [ -w /proc/sys/kernel/perf_event_paranoid ]; then
    echo -1 > /proc/sys/kernel/perf_event_paranoid
fi

DEMO_DIR=$(Rscript -e 'cat(system.file("demo", package="profdemo"))')

echo ""
echo "── bench comparisons ────────────────────────────────────"
Rscript "${DEMO_DIR}/04_bench_demo.R"

echo ""
echo "── Valgrind memory-leak reports ─────────────────────────"
bash "${DEMO_DIR}/02_valgrind_demo.sh"

echo ""
echo "── Linux perf cache statistics ──────────────────────────"
bash "${DEMO_DIR}/03_perf_demo.sh"

echo ""
echo "All done.  Reports are in /workspace/valgrind_reports/ and /workspace/perf_reports/"
echo "To run the interactive profvis session:  Rscript ${DEMO_DIR}/01_profvis_demo.R"
