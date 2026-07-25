#!/usr/bin/env bash
# inst/demo/02_valgrind_demo.sh
#
# Runs each leaky routine under Valgrind and prints the reports.
# Execute from inside the container:
#
#   bash /workspace/profdemo/inst/demo/02_valgrind_demo.sh
#
# Note: uses "R -d valgrind ..." rather than "valgrind Rscript ..." because
# the R command is a shell wrapper — passing it directly to valgrind would
# instrument bash instead of R.  The -d flag makes R exec valgrind on the
# real R binary itself.

set -euo pipefail

OUTDIR="/workspace/valgrind_reports"
mkdir -p "$OUTDIR"

# Helper: write an R script, run it under valgrind, show the definite leaks
vg() {
    local tag="$1"
    local rcode="$2"
    local script="${OUTDIR}/${tag}.R"
    local report="${OUTDIR}/${tag}.txt"

    printf '%s\n' "$rcode" > "$script"

    echo "=== Valgrind: $tag ==="
    R -d "valgrind --tool=memcheck --leak-check=full --show-leak-kinds=definite \
             --track-origins=yes --log-file=${report}" \
      --no-save --no-restore --file="$script" > /dev/null 2>&1 || true

    # Print only the definitively-lost blocks and the summary
    grep -E "(definitely lost in loss record|by 0x.*:.*\(|LEAK SUMMARY|definitely lost:|ERROR SUMMARY)" \
         "$report" | grep -v "^==[0-9]*==$" || echo "(no output — check $report)"
    echo ""
}

# ── 1. slow_sort: one malloc scratch buffer per call, never freed ─────────────
vg "slow_sort" "
library(profdemo)
for (i in 1:10) slow_sort(runif(1000))
"

# ── 2. leaky_matmul: one large calloc per call, never freed ───────────────────
vg "leaky_matmul" "
library(profdemo)
A <- matrix(runif(200*200), 200)
B <- matrix(runif(200*200), 200)
for (i in 1:5) leaky_matmul(A, B)
"

# ── 3. slow_string_join: n leaked intermediate buffers per call ───────────────
vg "slow_string_join" "
library(profdemo)
w <- letters[1:26]
for (i in 1:10) slow_string_join(w, '-')
"

echo "=== Overall leak totals ==="
for f in "$OUTDIR"/*.txt; do
    echo "--- $(basename "$f") ---"
    grep -E "definitely lost:" "$f" || echo "(not found)"
done
