#!/usr/bin/env bash
# inst/demo/03_perf_demo.sh
#
# Uses Linux perf stat to compare cache behaviour between the flawed routines
# and their efficient counterparts.
#
# Execute from /workspace inside the container (requires root or
# perf_event_paranoid <= 1):
#
#   echo -1 > /proc/sys/kernel/perf_event_paranoid   # if needed
#   bash /workspace/profdemo/inst/demo/03_perf_demo.sh

set -euo pipefail

OUTDIR="/workspace/perf_reports"
mkdir -p "$OUTDIR"

RSCRIPT="Rscript --vanilla"

perf_run() {
    local tag="$1"
    local expr="$2"
    echo "=== perf stat: $tag ==="
    perf stat \
        -e cache-references,cache-misses,instructions,cycles \
        --output "${OUTDIR}/${tag}.txt" \
        $RSCRIPT -e "library(profdemo); $expr" 2>&1 | tail -5
    echo "Full report: ${OUTDIR}/${tag}.txt"
    echo ""
}

MAT_EXPR_SLOW="m <- matrix(runif(2000*2000), 2000); for(i in 1:3) cache_unfriendly_colsum(m)"
MAT_EXPR_FAST="m <- matrix(runif(2000*2000), 2000); for(i in 1:3) colSums(m)"

# ── Cache miss comparison ─────────────────────────────────────────────────────
perf_run "colsum_unfriendly" "$MAT_EXPR_SLOW"
perf_run "colsum_base"       "$MAT_EXPR_FAST"

SORT_SLOW="x <- runif(5000); for(i in 1:50) slow_sort(x)"
SORT_FAST="x <- runif(5000); for(i in 1:50) sort(x)"

# ── Instruction count comparison ──────────────────────────────────────────────
perf_run "sort_bubble" "$SORT_SLOW"
perf_run "sort_base"   "$SORT_FAST"

echo "=== Cache-miss rates ==="
for f in "$OUTDIR"/*.txt; do
    echo "--- $(basename $f) ---"
    grep -E "cache-(references|misses)" "$f" | sed 's/^[[:space:]]*/    /' || true
done
