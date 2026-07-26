#!/usr/bin/env bash
# inst/demo/03_perf_demo.sh
#
# Profiles cache behaviour and CPU hotspots for the flawed vs fast routines.
#
# On a native Linux host: uses "perf stat" for hardware cache-miss counters.
# On Docker Desktop (Mac/Windows, linuxkit kernel): falls back to Google
# Performance Tools (gperftools CPU profiler) which is user-space only and
# works regardless of the kernel.
#
# Usage:
#   bash /workspace/profdemo/inst/demo/03_perf_demo.sh
#
# For perf on a native Linux host you may need:
#   echo -1 | sudo tee /proc/sys/kernel/perf_event_paranoid

set -euo pipefail

OUTDIR="/workspace/perf_reports"
mkdir -p "$OUTDIR"

# ── Detect whether perf is usable ─────────────────────────────────────────────
PERF_OK=false
if command -v perf >/dev/null 2>&1; then
    if perf stat true 2>&1 | grep -qE "(cycles|Performance counter)"; then
        PERF_OK=true
    fi
fi

# ── Helper: locate the gperftools CPU profiler library ────────────────────────
find_profiler_lib() {
    for lib in \
        /usr/lib/aarch64-linux-gnu/libprofiler.so.0 \
        /usr/lib/x86_64-linux-gnu/libprofiler.so.0 \
        /usr/local/lib/libprofiler.so.0
    do
        [ -f "$lib" ] && echo "$lib" && return 0
    done
    # fall back to ldconfig
    ldconfig -p 2>/dev/null | awk '/libprofiler/{print $NF}' | head -1
}

# ── Branch: perf stat path ────────────────────────────────────────────────────
if $PERF_OK; then
    echo "Using: Linux perf stat (native kernel)"
    echo ""

    perf_run() {
        local tag="$1"
        local expr="$2"
        echo "=== perf stat: $tag ==="
        perf stat \
            -e cache-references,cache-misses,instructions,cycles \
            --output "${OUTDIR}/${tag}_perf.txt" \
            Rscript --vanilla -e "library(profdemo); $expr" 2>&1 | tail -3
        echo "Full report: ${OUTDIR}/${tag}_perf.txt"
        echo ""
    }

    perf_run "colsum_unfriendly" \
        "m <- matrix(runif(2000*2000), 2000); for(i in 1:3) cache_unfriendly_colsum(m)"
    perf_run "colsum_base" \
        "m <- matrix(runif(2000*2000), 2000); for(i in 1:3) colSums(m)"
    perf_run "sort_bubble" \
        "x <- runif(5000); for(i in 1:50) slow_sort(x)"
    perf_run "sort_base" \
        "x <- runif(5000); for(i in 1:50) sort(x)"

    echo "=== Cache-miss rates ==="
    for f in "$OUTDIR"/*_perf.txt; do
        echo "--- $(basename "$f") ---"
        grep -E "cache-(references|misses)" "$f" | sed 's/^[[:space:]]*/    /' || true
    done

# ── Branch: gperftools CPU profiler fallback ──────────────────────────────────
else
    echo "perf stat unavailable (likely a linuxkit / Docker Desktop kernel)."
    echo "Falling back to Google Performance Tools CPU profiler."
    echo ""

    PROFLIB=$(find_profiler_lib || true)
    if [ -z "$PROFLIB" ]; then
        echo "ERROR: libprofiler not found. Install google-perftools and retry."
        exit 1
    fi
    echo "Profiler library: $PROFLIB"
    echo ""

    PPROF=$(command -v google-pprof pprof 2>/dev/null | head -1 || true)

    gperf_run() {
        local tag="$1"
        local rcode="$2"
        local prof_out="${OUTDIR}/${tag}.prof"
        local txt_out="${OUTDIR}/${tag}_gperf.txt"
        local script="${OUTDIR}/${tag}.R"

        printf '%s\n' "$rcode" > "$script"

        echo "=== gperftools: $tag ==="

        # Use R shell wrapper (not the raw binary) so libR.so is on the path.
        # LD_PRELOAD and CPUPROFILE are inherited through the exec chain.
        LD_PRELOAD="$PROFLIB" CPUPROFILE="$prof_out" \
            R --no-save --no-restore --quiet --file="$script" \
            > /dev/null 2>&1 || true

        # gperftools writes one file per forked child; grab the largest
        BEST=$(ls -S "${prof_out}"* 2>/dev/null | head -1 || true)

        if [ -n "$BEST" ] && [ -s "$BEST" ] && [ -n "$PPROF" ]; then
            $PPROF --text "$(which R)" "$BEST" > "$txt_out" 2>/dev/null || true
            if [ -s "$txt_out" ]; then
                echo "Top functions by CPU samples:"
                head -15 "$txt_out" | sed 's/^/  /'
            else
                echo "Profile saved: $BEST  (symbolisation failed — run pprof manually)"
            fi
        else
            echo "Profile saved: ${prof_out}*"
            echo "Symbolise with:  google-pprof --text \$(which R) $BEST"
        fi
        echo ""
    }

    gperf_run "colsum_unfriendly" "
library(profdemo)
m <- matrix(runif(1000*1000), 1000)
for (i in 1:20) cache_unfriendly_colsum(m)
q(save='no')
"

    gperf_run "colsum_base" "
library(profdemo)
m <- matrix(runif(1000*1000), 1000)
for (i in 1:20) colSums(m)
q(save='no')
"

    gperf_run "sort_bubble" "
library(profdemo)
x <- runif(3000)
for (i in 1:50) slow_sort(x)
q(save='no')
"

    gperf_run "sort_base" "
library(profdemo)
x <- runif(3000)
for (i in 1:50) sort(x)
q(save='no')
"

    echo "All profile files in $OUTDIR/"
    echo "Interactive flame graph (if graphviz is installed):"
    echo "  google-pprof --pdf \$(which R) ${OUTDIR}/sort_bubble.prof* > /workspace/sort_bubble.pdf"
fi
