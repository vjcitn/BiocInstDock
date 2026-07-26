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

### API keys and outbound networking

`ellmer` reads provider credentials from standard environment variables:

| Provider | Variable |
|----------|----------|
| Anthropic (Claude) | `ANTHROPIC_API_KEY` |
| OpenAI (GPT-4o, o3, …) | `OPENAI_API_KEY` |
| Google (Gemini) | `GEMINI_API_KEY` |

Pass them at `docker run` time so they are never baked into the image:

```bash
docker run --rm -p 8787:8787 \
  -e PASSWORD=rstudio \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  profdemo
```

**No extra port mapping is needed for outbound API calls.**  When `ellmer`
contacts a provider it opens an outbound HTTPS connection on port 443.
Docker containers have outbound internet access by default — the host's
network stack NATs the traffic out.  The `-p 8787:8787` flag only controls
*inbound* connections to RStudio Server; it has no effect on outbound calls.

If your host is behind a corporate proxy or firewall that restricts outbound
HTTPS, pass the proxy settings into the container as well:

```bash
docker run --rm -p 8787:8787 \
  -e PASSWORD=rstudio \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  -e https_proxy=http://proxy.example.com:8080 \
  -e http_proxy=http://proxy.example.com:8080 \
  -e no_proxy=localhost,127.0.0.1 \
  profdemo
```

---

## Installing R packages at session time (r2u)

When you start a container session and want to install an R package that was not
baked into the image, use **apt** rather than `install.packages()` wherever
possible.  On amd64 the container has the
[r2u](https://eddelbuettel.github.io/r2u/) repository configured, which
provides pre-built `.deb` packages for every CRAN and Bioconductor package.
Installation takes seconds instead of minutes because nothing is compiled.

```bash
# CRAN package
apt-get install -y r-cran-ggplot2

# Bioconductor package (installs the package + all its dependencies)
apt-get install -y r-bioc-deseq2
apt-get install -y r-bioc-summarizedexperiment
```

The naming convention is `r-cran-<lowercase-name>` and
`r-bioc-<lowercase-name>`.  Hyphens in package names become hyphens in the
`.deb` name (e.g. `r-cran-data-table`, `r-bioc-bioc-generics`).

If a package is not yet in r2u, `apt-get install` simply returns "package not
found" and you fall back to the usual:

```r
install.packages("mypkg")
BiocManager::install("mypkg")
```

> **arm64 note:** r2u only publishes amd64 binaries.  On arm64 (Docker Desktop
> on Apple Silicon) `apt-get install r-cran-*` will find nothing and you must
> use `install.packages()` / `BiocManager::install()` instead, which compile
> from source.  The profiling workflow below works identically on both
> architectures; installs just take longer on arm64.

---

## Profiling an external package from source

The same toolchain that analyses `profdemo` applies to any R package with C or
C++ code.  The key requirement is that the package is compiled with **debug
symbols and no optimisation** (`-g -O0`) so that profiler output resolves to
source lines rather than raw addresses.

### Step 1 — Install dependencies as binaries, recompile only the target

Installing dependencies from source is slow and unnecessary — you only need
debug symbols in the package you are profiling.  Use
**[r2u](https://eddelbuettel.github.io/r2u/)** to get pre-built `.deb` packages
for all of CRAN and Bioconductor in seconds, then recompile just the target
package with `-g -O0`.

> **Architecture note:** r2u supports **amd64 only**.  On arm64 (e.g. Docker
> Desktop on Apple Silicon) `apt` will find no r2u packages and
> `install.packages()` / `BiocManager::install()` falls back to CRAN source
> builds automatically — the commands below work on both architectures, they
> are just faster on amd64.

```bash
cd /workspace
git clone https://github.com/username/reponame   # or Bioconductor URL

# Install all dependencies as binaries via r2u (amd64) or CRAN source (arm64)
apt-get install -y r-cran-reponame   # replaces R -e "install.packages(...)"
# For Bioconductor packages:
apt-get install -y r-bioc-deseq2     # installs DESeq2 + all deps as .deb

# Now recompile only the target package with debug symbols
mkdir -p ~/.R
echo 'CFLAGS   = -g -O0' >> ~/.R/Makevars
echo 'CXXFLAGS = -g -O0' >> ~/.R/Makevars
R CMD INSTALL --preclean reponame
```

This leaves all dependencies as optimised release binaries (so their
performance is realistic) while the target package is compiled with full
debug information for readable profiler and Valgrind output.

### Step 2 — Write a profiling script

Create a script (`/workspace/scripts/mypkg_profile.R`) that:

- Loads the package and constructs realistic inputs
- Has a **warm-up section** (small inputs, exercises all code paths once)
- Has a **scaling section** (varying N or other size parameters with `system.time`)
- Has a **sustained section** (large inputs, `epsilon = 0` or high `max_iter` to
  prevent early convergence, repeated runs) so the CPU profiler accumulates enough
  samples to resolve individual functions

See `scripts/mdclust_profile.R` for a worked example against the
[mdclust](https://github.com/Herbermann/mdclust) package.

### Step 3 — Valgrind (memory leaks and errors)

```bash
R -d "valgrind --tool=memcheck --leak-check=full --show-leak-kinds=definite" \
  --no-save --no-restore \
  --file=/workspace/scripts/mypkg_profile.R
```

Stack traces will name the C/C++ source file and line number for every
`definitely lost` block, provided the package was built with `-g`.

### Step 4 — gperftools CPU profiler

On Docker Desktop (Mac/Windows) `perf stat` is unavailable because the
container runs on a linuxkit kernel.  Use the gperftools profiler instead,
which is user-space and works everywhere.

**Important:** run the real R binary directly (not the `R` wrapper script) and
set `LD_LIBRARY_PATH` so it can find `libR.so`.  Also set
`OPENBLAS_NUM_THREADS=1` to suppress OpenBLAS thread-spinning, which otherwise
dominates the profile with `__GI_sched_yield` calls and obscures your code.

```bash
mkdir -p /workspace/perf_reports

OPENBLAS_NUM_THREADS=1 \
  LD_LIBRARY_PATH=/usr/local/lib/R/lib:$LD_LIBRARY_PATH \
  LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libprofiler.so.0 \
  CPUPROFILE=/workspace/perf_reports/mypkg.prof \
  /usr/local/lib/R/bin/exec/R \
    --no-save --no-restore --quiet \
    --file=/workspace/scripts/mypkg_profile.R
```

*(On amd64 replace `aarch64-linux-gnu` with `x86_64-linux-gnu`.)*

### Step 5 — Symbolise the profile

gperftools writes one file per forked subprocess.  The largest file is the main
R process.

```bash
# Identify the largest profile file
ls -lSh /workspace/perf_reports/mypkg.prof*

# Text report — use the real R binary for symbol lookup
google-pprof --text \
  /usr/local/lib/R/bin/exec/R \
  $(ls -S /workspace/perf_reports/mypkg.prof* | head -1)
```

Useful pprof commands in interactive mode (`google-pprof` with no `--text`):

| Command | Effect |
|---------|--------|
| `top20` | Top 20 functions by self samples |
| `top20 -cum` | Top 20 by cumulative (inclusive) samples |
| `list funcname` | Annotate source lines for functions matching `funcname` |
| `pdf` | Write a call-graph PDF to `/tmp/pprof.*.pdf` |
| `quit` | Exit |

### Reading the output

| Symbol pattern | Likely source |
|----------------|---------------|
| `__GI_sched_yield` + `openblas_read_env` | OpenBLAS thread spinning — set `OPENBLAS_NUM_THREADS=1` |
| `arma::Proxy::operator[]` / `arma::eOp` | Armadillo lazy expression evaluation (element-wise ops) |
| `arma::op_shuffle::apply_direct` | Per-iteration data shuffle — cost grows linearly with N |
| `std::__unguarded_partition` | `std::sort` inside initialisation |
| `dgemm_kernel_*` | BLAS matrix multiply (centroid update) |
| `__GI___exp` / `__log_finite` | Softmax / log-likelihood in the inner loop |

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
    ├── run_all_demos.sh              # orchestrates all four demos
    ├── mdclust_profile.R             # worked example: mdclust (RcppArmadillo)
    └── deseq2_profile.R              # worked example: DESeq2 (fitDisp/fitBeta)
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
