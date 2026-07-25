#' Join a character vector with cascading memory leaks
#'
#' Each iteration allocates a new buffer for the growing result and discards
#' the previous one without calling \code{free()}.  For a vector of n strings
#' this produces n leaked malloc blocks, all visible in Valgrind's leak
#' summary.  The algorithm is also O(n^2) in total string length because the
#' accumulated prefix is copied on every step.
#'
#' @param strings Character vector of strings to join.
#' @param sep     Separator inserted between elements (length-1 character).
#' @return A single character string.
#' @export
slow_string_join <- function(strings, sep = ", ") {
    .Call("slow_string_join", as.character(strings), as.character(sep)[1L])
}
