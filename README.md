# BiocInstDock

A Docker-based teaching environment for profiling and debugging C code called from R.
The repository ships a small R package — **profdemo** — whose C routines are
intentionally broken in instructive ways: O(n²) algorithms, cache-hostile memory
access, and `malloc` calls with no matching `free`.  Each flaw is designed to be
caught by a different tool in the profiling stack.

The container runs **RStudio Server**, so `profvis` flame graphs and other HTML
reports render directly in a browser at `http://localhost:8787` — no extra setup
required.

[`ellmer`](https://ellmer.tidyverse.org/) and [`btw`](https://posit-dev.github.io/btw/)
are also pre-installed, so users can interrogate code and results with an LLM
directly from the R console without leaving the container.

---

## Tools demonstrated

| Tool | What it finds |
|------|---------------|
| [`profvis`](https://rstudio.github.io/profvis/) | Flame graphs showing where R + C time is spent |
| [`bench`](https://bench.r-lib.org/) | Wall-clock and allocation comparisons between slow and fast versions |
| [Valgrind memcheck](https://valgrind.org/) | Exact `malloc` leak sites with full C stack traces |
| [Linux perf](https://perf.wiki.kernel.org/) | Hardware cache-miss rates for memory-access pattern analysis |
| [`ellmer`](https://ellmer.tidyverse.org/) | Chat with LLMs (Claude, GPT-4o, Gemini, …) from the R console |
| [`btw`](https://posit-dev.github.io/btw/) | Share R session context with an LLM to get grounded, accurate help |

---

## The eight intentional flaws

| # | Function | Flaw | Tool |
|---|----------|------|------|
| 1 | `slow_sort` | O(n²) bubble sort instead of O(n log n) | profvis, bench |
| 2 | `slow_sort` | `malloc` scratch buffer never `free`'d | Valgrind |
| 3 | `slow_cumsum` | Re-sums from index 0 each iteration (O(n²)) instead of carrying a running total | profvis, bench |
| 4 | `cache_unfriendly_colsum` | Row-outer / column-inner loop on a column-major R matrix — maximises cache misses | perf stat |
| 5 | `leaky_matmul` | Naive O(n³) triple loop with no cache tiling | profvis, bench |
| 6 | `leaky_matmul` | Result assembled in a `malloc`'d buffer that is never `free`'d | Valgrind |
| 7 | `slow_string_join` | Reallocates and copies the accumulator on every iteration (O(n²) in total chars); each old buffer leaks | Valgrind |
| 8 | `slow_string_join` | Final accumulator buffer also never `free`'d | Valgrind |

---

## Quick start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (Desktop or Engine)
- For the `perf` demo: Linux host, or Docker with `--privileged`

### Build the image

```bash
git clone https://github.com/vjcitn/BiocInstDock.git
cd BiocInstDock
docker build -t profdemo .
```

The build installs Valgrind, Linux perf tools, Google perftools, RStudio Server,
and the `profvis` / `bench` R packages, then compiles and installs **profdemo**.

---

## RStudio Server — interactive profvis in the browser

Start the container and open RStudio in any browser:

```bash
docker run --rm -p 8787:8787 -e PASSWORD=rstudio profdemo
```

Then navigate to **http://localhost:8787** and log in:

| Field | Value |
|-------|-------|
| Username | `rstudio` |
| Password | `rstudio` |

From the RStudio console, run the profvis demo and the flame graph opens
in a pop-up viewer overlay (RStudio Server behaviour — click the external-link
icon to open it as a standalone browser tab):

```r
source(system.file("demo/01_profvis_demo.R", package = "profdemo"))
```

Or interactively:

```r
library(profdemo)
library(profvis)

x <- runif(5000)
profvis({
  for (i in 1:20) slow_sort(x)      # bubble sort — wide bar
  for (i in 1:20) sort(x)           # radix sort  — invisible
})
```

To persist work between sessions mount a host directory:

```bash
docker run --rm -p 8787:8787 -e PASSWORD=rstudio \
  -v "$HOME/profdemo_work:/home/rstudio" profdemo
```

---

## Running the demos from the command line

### bench — timing and allocation comparisons

```bash
docker run --rm profdemo Rscript /workspace/profdemo/inst/demo/04_bench_demo.R
```

Example output (arm64):

```
── 1. Sorting (n = 3 000) ──────────────────────────────────────────
  expression     min  median `itr/sec`
  bubble      3.94ms  3.94ms      253.     # O(n^2) bubble sort
  builtin    65.58µs 70.48µs    13906.     # R's radix sort — 56x faster

── 2. Cumulative sum (n = 2 000) ───────────────────────────────────
  quadratic    985µs  1.02ms      982.     # re-sums from 0 each step
  builtin       15µs 17.02µs    58509.     # single pass — 60x faster

── 4. Matrix multiply (200 x 200) ──────────────────────────────────
  naive_leak    4.7ms   5.04ms      144.   # triple loop, no tiling, leaks
  builtin     173.3µs 175.35µs     5370.   # BLAS — 29x faster
```

### Valgrind — memory leak detection

```bash
docker run --rm profdemo bash /workspace/profdemo/inst/demo/02_valgrind_demo.sh
```

Valgrind traces every `malloc` that is never `free`'d back to the exact C source
line:

```
=== Valgrind: slow_sort ===
==8== 80,000 bytes in 10 blocks are definitely lost
==8==    by 0x...: slow_sort (sorting.c:25)        ← scratch buffer, line 25

=== Valgrind: leaky_matmul ===
==32== 1,600,000 bytes in 5 blocks are definitely lost
==32==    by 0x...: leaky_matmul (matrix_ops.c:62)  ← result buffer, line 62

=== Valgrind: slow_string_join ===
==56== 7,030 bytes in 270 blocks are definitely lost
==56==    by 0x...: slow_string_join (string_ops.c:29)  ← initial malloc
==56==    by 0x...: slow_string_join (string_ops.c:42)  ← loop malloc
```

> **Note:** the demo uses `R -d "valgrind ..."` rather than `valgrind Rscript ...`
> because the `R` command is a bash wrapper.  The `-d` flag makes R exec valgrind
> directly on the real binary, which is required for leak detection to work.

### Linux perf — cache statistics

```bash
# --privileged is needed to lower perf_event_paranoid
docker run --rm --privileged profdemo bash /workspace/profdemo/inst/demo/03_perf_demo.sh
```

Compares cache-reference and cache-miss counts between `cache_unfriendly_colsum`
(row-first traversal of a column-major matrix) and `colSums()`.

### Run all demos at once

```bash
docker run --rm --privileged profdemo bash /workspace/scripts/run_all_demos.sh
```

---

## Using LLMs from R (ellmer + btw)

`ellmer` and `btw` are pre-installed so you can ask an LLM questions about your
profiling results without leaving RStudio.

### Quick start with ellmer

```r
library(ellmer)

# Pick a provider — set the matching API key as an environment variable first:
#   Sys.setenv(ANTHROPIC_API_KEY = "sk-ant-...")
#   Sys.setenv(OPENAI_API_KEY    = "sk-...")
chat <- chat_claude()   # or chat_openai(), chat_gemini(), …
chat$chat("What is the time complexity of bubble sort and why is it slow for large n?")
```

### Providing R session context with btw

`btw` lets you snapshot your current session — loaded packages, data frames,
function definitions — and attach it as context before asking a question:

```r
library(ellmer)
library(btw)
library(profdemo)

x     <- runif(3000)
slow  <- system.time(slow_sort(x))
fast  <- system.time(sort(x))

chat <- chat_claude()
chat$chat(btw(
  "I measured two sort implementations:",
  slow, fast,
  "The slow one uses a C bubble sort. Why is it so much slower,
   and what would a better replacement look like in C?"
))
```

> **API keys:** `ellmer` reads keys from environment variables
> (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, etc.).
> Pass them at container start time so they are never baked into the image:
>
> ```bash
> docker run --rm -p 8787:8787 \
>   -e PASSWORD=rstudio \
>   -e ANTHROPIC_API_KEY=sk-ant-... \
>   profdemo
> ```

---

## Repository layout

```
BiocInstDock/
├── Dockerfile                        # rocker/rstudio base + profiling tools
├── profdemo/                         # R package with intentionally flawed C code
│   ├── DESCRIPTION
│   ├── NAMESPACE
│   ├── R/
│   │   ├── sorting.R                 # slow_sort(), slow_cumsum()
│   │   ├── matrix_ops.R              # cache_unfriendly_colsum(), leaky_matmul()
│   │   └── string_ops.R              # slow_string_join()
│   ├── src/
│   │   ├── sorting.c                 # Flaws 1–3
│   │   ├── matrix_ops.c              # Flaws 4–6
│   │   ├── string_ops.c              # Flaws 7–8
│   │   └── register.c                # R_registerRoutines
│   └── inst/demo/
│       ├── 01_profvis_demo.R         # profvis flame graph session
│       ├── 02_valgrind_demo.sh       # Valgrind leak reports
│       ├── 03_perf_demo.sh           # Linux perf cache stats
│       └── 04_bench_demo.R           # bench timing comparisons
└── scripts/
    └── run_all_demos.sh              # orchestrates all four demos
```

---

## Multi-architecture support

The base image (`rocker/rstudio`) publishes manifests for both `linux/amd64` and
`linux/arm64`.  All apt packages are available on both architectures.  Build on
whichever host you have and the image will be native.  To produce a single
multi-arch manifest for a registry:

```bash
docker buildx create --use
docker buildx build --platform linux/amd64,linux/arm64 \
  -t yourrepo/profdemo:latest --push .
```
