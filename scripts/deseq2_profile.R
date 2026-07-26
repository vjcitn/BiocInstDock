# deseq2_profile.R
#
# Exercises the three C++ entry points in DESeq2:
#
#   fitDisp()      — MAP/MLE dispersion estimation via Armijo line search.
#                    Per-gene loop; inner iterations call log_posterior() and
#                    dlog_posterior() which evaluate lgamma, digamma, and
#                    (when useCR=TRUE) matrix determinants.
#
#   fitDispGrid()  — Coarse grid search for genes where fitDisp() fails to
#                    converge.  Evaluates log_posterior() at each grid point
#                    for each non-converged gene.
#
#   fitBeta()      — NB GLM coefficient fitting via IRLS (QR path by default).
#                    Per-gene loop; each IRLS step does qr_econ() + solve().
#                    After convergence computes the hat matrix diagonal via a
#                    triple nested loop over samples × design columns.
#
# Suitable for:
#   Valgrind:
#     R -d "valgrind --tool=memcheck --leak-check=full \
#       --show-leak-kinds=definite" \
#       --no-save --no-restore --file=deseq2_profile.R
#
#   gperftools:
#     OPENBLAS_NUM_THREADS=1 \
#     LD_LIBRARY_PATH=/usr/local/lib/R/lib:$LD_LIBRARY_PATH \
#     LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libprofiler.so.0 \
#     CPUPROFILE=/workspace/perf_reports/deseq2.prof \
#     /usr/local/lib/R/bin/exec/R \
#       --no-save --no-restore --quiet \
#       --file=/workspace/scripts/deseq2_profile.R
#
#   profvis (in RStudio):
#     profvis::profvis(source("deseq2_profile.R"))
#
# Installation (run once before profiling):
#   cd /workspace
#   git clone https://git.bioconductor.org/packages/DESeq2
#   mkdir -p ~/.R
#   echo 'CFLAGS   = -g -O0' >> ~/.R/Makevars
#   echo 'CXXFLAGS = -g -O0' >> ~/.R/Makevars
#   R -e "BiocManager::install(c('SummarizedExperiment','BiocGenerics','S4Vectors','IRanges','GenomicRanges','MatrixGenerics','Biobase','locfit'))"
#   R CMD INSTALL --preclean DESeq2

suppressPackageStartupMessages(library(DESeq2))

set.seed(42)

# ── Helper: simulate an RNA-seq count matrix ──────────────────────────────────
# n_genes  = number of genes (rows)
# n_samples = number of samples per condition (2 conditions total)
# de_frac  = fraction of genes that are differentially expressed
# Returns a list suitable for DESeqDataSetFromMatrix()
sim_rnaseq <- function(n_genes, n_samples, de_frac = 0.1) {
    n_total  <- n_samples * 2
    condition <- factor(rep(c("ctrl", "trt"), each = n_samples))

    # baseline mean expression: log-normal, typical RNA-seq range
    base_mean <- exp(rnorm(n_genes, mean = 4, sd = 2))
    # dispersion: roughly follows a 1/mean trend + noise (typical RNA-seq)
    dispersion <- 0.1 + 1 / base_mean + rnorm(n_genes, sd = 0.1)^2
    dispersion <- pmax(dispersion, 0.01)

    # log2 fold-changes for DE genes
    lfc <- rep(0, n_genes)
    de_idx <- sample(n_genes, floor(n_genes * de_frac))
    lfc[de_idx] <- rnorm(length(de_idx), sd = 1.5)

    # size factors (mild library size variation)
    sf <- exp(rnorm(n_total, sd = 0.3))

    counts <- matrix(0L, nrow = n_genes, ncol = n_total)
    for (j in seq_len(n_total)) {
        fc <- if (condition[j] == "trt") 2^lfc else rep(1, n_genes)
        mu <- base_mean * fc * sf[j]
        counts[, j] <- rnbinom(n_genes, mu = mu, size = 1 / dispersion)
    }
    rownames(counts) <- paste0("gene", seq_len(n_genes))
    colnames(counts) <- paste0("sample", seq_len(n_total))

    list(
        counts    = counts,
        colData   = data.frame(condition = condition,
                               row.names = colnames(counts))
    )
}

# convenience wrapper: build DESeqDataSet and run full pipeline
run_deseq2 <- function(n_genes, n_samples, quiet = TRUE) {
    d <- sim_rnaseq(n_genes, n_samples)
    dds <- DESeqDataSetFromMatrix(
        countData = d$counts,
        colData   = d$colData,
        design    = ~ condition
    )
    # suppress verbose output during profiling
    suppressMessages(DESeq(dds, quiet = quiet))
}

# ── 1. Warm-up: small dataset, exercises all three C++ functions ──────────────
cat("-- warm-up (200 genes, 3 samples/condition) --\n")
dds <- run_deseq2(n_genes = 200, n_samples = 3)
res <- results(dds)
cat("   DE genes (padj < 0.05):", sum(res$padj < 0.05, na.rm = TRUE), "\n\n")

# ── 2. Scale genes — fitDisp and fitBeta cost grows linearly in n_genes ───────
# fitDisp:     outer loop over y_n = n_genes
# fitBeta:     outer loop over y_n = n_genes, hat matrix triple loop per gene
# fitDispGrid: triggered for non-converged genes (subset of n_genes)
cat("-- scaling genes (4 samples/condition) --\n")
for (ng in c(1000, 5000, 15000)) {
    t <- system.time(dds <- run_deseq2(n_genes = ng, n_samples = 4))
    cat(sprintf("   genes=%6d  elapsed=%5.1fs\n", ng, t["elapsed"]))
}
cat("\n")

# ── 3. Scale samples — fitBeta IRLS and hat matrix cost grows with n_samples ──
# QR decomposition in fitBeta is O(n_samples * p^2) per gene per IRLS step.
# Hat matrix diagonal triple loop is O(n_samples * p^2) per gene.
cat("-- scaling samples (5 000 genes) --\n")
for (ns in c(3, 8, 20)) {
    t <- system.time(dds <- run_deseq2(n_genes = 5000, n_samples = ns))
    cat(sprintf("   samples/condition=%2d  elapsed=%5.1fs\n", ns, t["elapsed"]))
}
cat("\n")

# ── 4. Isolate estimateDispersions — fitDisp + fitDispGrid ───────────────────
# Run size factor estimation separately so the timing isolates the dispersion
# step (the dominant C++ cost for typical gene counts).
cat("-- isolating estimateDispersions (10 000 genes, 4 samples/condition) --\n")
d <- sim_rnaseq(10000, 4)
dds_base <- DESeqDataSetFromMatrix(d$counts, d$colData, ~ condition)
dds_base <- suppressMessages(estimateSizeFactors(dds_base))
t <- system.time(
    dds_base <- suppressMessages(estimateDispersions(dds_base))
)
cat(sprintf("   estimateDispersions: %.1fs\n\n", t["elapsed"]))

# ── 5. Isolate nbinomWaldTest — fitBeta ───────────────────────────────────────
cat("-- isolating nbinomWaldTest / fitBeta (10 000 genes, 4 samples/condition) --\n")
t <- system.time(
    dds_wald <- suppressMessages(nbinomWaldTest(dds_base))
)
cat(sprintf("   nbinomWaldTest: %.1fs\n\n", t["elapsed"]))

# ── 6. Sustained run for CPU profiler ─────────────────────────────────────────
# Large gene count, moderate samples. Repeated to accumulate profiler samples
# across fitDisp (lgamma/digamma, CR determinant), fitBeta (QR, hat matrix),
# and fitDispGrid (grid log_posterior evaluations).
cat("-- sustained run (20 000 genes, 6 samples/condition, 3 reps) --\n")
for (rep in seq_len(3)) {
    t <- system.time(dds <- run_deseq2(n_genes = 20000, n_samples = 6))
    res <- results(dds)
    cat(sprintf("   rep=%d  elapsed=%5.1fs  DE=%d\n",
                rep, t["elapsed"],
                sum(res$padj < 0.05, na.rm = TRUE)))
}

cat("\nDone.\n")
q(save = "no")
