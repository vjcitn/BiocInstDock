/*
 * sorting.c — intentionally flawed sorting and scan routines.
 *
 * FLAW 1 (slow_sort):   Bubble sort — O(n^2) comparisons.
 *                        R_qsort_double() gives O(n log n).
 * FLAW 2 (slow_sort):   Scratch buffer allocated with malloc() but never
 *                        freed — visible as a definite leak in Valgrind.
 * FLAW 3 (slow_cumsum): Recomputes the running total from index 0 on every
 *                        iteration — O(n^2) work for an O(n) problem.
 */

#include <R.h>
#include <Rinternals.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ */
SEXP slow_sort(SEXP x_)
{
    int n = LENGTH(x_);
    double *x = REAL(x_);

    /* FLAW 2: raw malloc — R's garbage collector cannot see this block.
     * Valgrind will report it as "definitely lost" after the call returns. */
    double *tmp = (double *) malloc(n * sizeof(double));
    if (!tmp) error("slow_sort: malloc failed");
    memcpy(tmp, x, n * sizeof(double));

    SEXP result = PROTECT(allocVector(REALSXP, n));
    double *out = REAL(result);
    memcpy(out, tmp, n * sizeof(double));

    /* FLAW 1: O(n^2) bubble sort */
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - i - 1; j++) {
            if (out[j] > out[j + 1]) {
                double t  = out[j];
                out[j]   = out[j + 1];
                out[j + 1] = t;
            }
        }
    }

    /* BUG: free(tmp) is intentionally omitted — this is the memory leak */

    UNPROTECT(1);
    return result;
}

/* ------------------------------------------------------------------ */
SEXP slow_cumsum(SEXP x_)
{
    int n = LENGTH(x_);
    double *x = REAL(x_);

    SEXP result = PROTECT(allocVector(REALSXP, n));
    double *out = REAL(result);

    /* FLAW 3: Re-sums from j=0 for every i instead of carrying a running
     * total.  Work grows as 1+2+...+n = O(n^2). */
    for (int i = 0; i < n; i++) {
        out[i] = 0.0;
        for (int j = 0; j <= i; j++) {   /* redundant inner loop */
            out[i] += x[j];
        }
    }

    UNPROTECT(1);
    return result;
}
