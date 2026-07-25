#' Sort a numeric vector using bubble sort
#'
#' Intentionally O(n^2).  Also leaks one malloc'd scratch buffer per call
#' (detectable with Valgrind --leak-check=full).
#'
#' @param x Numeric vector to sort.
#' @return Sorted numeric vector.
#' @export
slow_sort <- function(x) {
    .Call("slow_sort", as.double(x))
}

#' Cumulative sum via repeated full scan
#'
#' Intentionally O(n^2): for each position i the C routine sums from index 0
#' to i instead of carrying a running total.
#'
#' @param x Numeric vector.
#' @return Numeric vector of cumulative sums.
#' @export
slow_cumsum <- function(x) {
    .Call("slow_cumsum", as.double(x))
}
