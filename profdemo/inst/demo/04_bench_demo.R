# inst/demo/04_bench_demo.R
#
# Uses the bench package to time flawed vs. fast implementations side-by-side
# and display memory allocation counts.
#
#   Rscript /workspace/profdemo/inst/demo/04_bench_demo.R

library(profdemo)
library(bench)

cat("\n── 1. Sorting (n = 3 000) ──────────────────────────────────────────\n")
x <- runif(3000)
print(mark(
    bubble  = slow_sort(x),
    builtin = sort(x),
    iterations = 20,
    check = FALSE   # results differ in attribute details
))

cat("\n── 2. Cumulative sum (n = 2 000) ───────────────────────────────────\n")
y <- runif(2000)
print(mark(
    quadratic = slow_cumsum(y),
    builtin   = cumsum(y),
    iterations = 50
))

cat("\n── 3. Column sums (1 000 x 1 000 matrix) ───────────────────────────\n")
mat <- matrix(runif(1e6), 1000)
print(mark(
    cache_bad = cache_unfriendly_colsum(mat),
    colSums   = colSums(mat),
    iterations = 10
))

cat("\n── 4. Matrix multiply (200 x 200) ──────────────────────────────────\n")
A <- matrix(runif(200 * 200), 200)
B <- matrix(runif(200 * 200), 200)
print(mark(
    naive_leak = leaky_matmul(A, B),
    builtin    = A %*% B,
    iterations = 5,
    check = FALSE
))

cat("\n── 5. String join (200 words) ───────────────────────────────────────\n")
words <- vapply(seq_len(200), function(i)
    paste(sample(letters, 8, TRUE), collapse = ""), character(1))
print(mark(
    leaky_join = slow_string_join(words, "-"),
    paste      = paste(words, collapse = "-"),
    iterations = 100
))

cat("\nNote: bench::mark() reports median time and total allocated memory.\n",
    "Memory figures include R heap allocations; C-level leaks are not\n",
    "counted here — use Valgrind (02_valgrind_demo.sh) for those.\n")
