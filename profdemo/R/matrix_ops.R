#' Column sums with cache-unfriendly traversal
#'
#' The underlying C routine iterates rows in the outer loop and columns in the
#' inner loop.  Because R matrices are column-major, this produces non-sequential
#' memory access (stride = nrow), causing frequent cache misses.
#' Linux \code{perf stat} will report an elevated \code{cache-misses} count
#' compared with \code{colSums()}.
#'
#' @param mat Numeric matrix.
#' @return Numeric vector of column sums.
#' @export
cache_unfriendly_colsum <- function(mat) {
    storage.mode(mat) <- "double"
    .Call("cache_unfriendly_colsum", mat)
}

#' Naive matrix multiply with a memory leak
#'
#' Uses an O(m*k*n) triple loop with no cache tiling.  Assembles the result
#' in a \code{malloc()}'d buffer that is never freed (Valgrind will report it).
#'
#' @param A Numeric matrix (m x k).
#' @param B Numeric matrix (k x n).
#' @return Numeric matrix (m x n).
#' @export
leaky_matmul <- function(A, B) {
    storage.mode(A) <- "double"
    storage.mode(B) <- "double"
    .Call("leaky_matmul", A, B)
}
