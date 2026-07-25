# inst/demo/01_profvis_demo.R
#
# Demonstrates R-level profiling with profvis.
# Run inside R (or RStudio) after installing the package:
#
#   install.packages("profvis")
#   devtools::install("/workspace/profdemo")   # or R CMD INSTALL
#   source(system.file("demo/01_profvis_demo.R", package = "profdemo"))

library(profdemo)
library(profvis)

# ── 1. slow_sort vs base::sort ────────────────────────────────────────────────
n <- 5000
x <- runif(n)

p_sort <- profvis({
    for (i in seq_len(10)) slow_sort(x)   # bubble sort — watch the flame graph
    for (i in seq_len(10)) sort(x)        # R's built-in (radix / merge sort)
})
print(p_sort)
# Expected: slow_sort bar dominates; sort() is nearly invisible.

# ── 2. slow_cumsum vs base::cumsum ────────────────────────────────────────────
y <- runif(2000)

p_cumsum <- profvis({
    for (i in seq_len(20)) slow_cumsum(y)  # O(n^2) scan
    for (i in seq_len(20)) cumsum(y)       # O(n)
})
print(p_cumsum)

# ── 3. cache_unfriendly_colsum vs colSums ────────────────────────────────────
mat <- matrix(runif(1000 * 1000), nrow = 1000)

p_colsum <- profvis({
    for (i in seq_len(5)) cache_unfriendly_colsum(mat)
    for (i in seq_len(5)) colSums(mat)
})
print(p_colsum)

# ── 4. leaky_matmul vs %*% ────────────────────────────────────────────────────
A <- matrix(runif(200 * 200), nrow = 200)
B <- matrix(runif(200 * 200), nrow = 200)

p_matmul <- profvis({
    for (i in seq_len(3)) leaky_matmul(A, B)
    for (i in seq_len(3)) A %*% B
})
print(p_matmul)

# ── 5. slow_string_join vs paste ──────────────────────────────────────────────
words <- replicate(500, paste(sample(letters, 6, replace = TRUE), collapse = ""))

p_str <- profvis({
    for (i in seq_len(20)) slow_string_join(words, sep = "-")
    for (i in seq_len(20)) paste(words, collapse = "-")
})
print(p_str)

message("\nAll profvis profiles complete.  Examine each htmlwidget for flame graphs.")
