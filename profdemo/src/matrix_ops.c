/*
 * matrix_ops.c — cache-hostile matrix routines with a memory leak.
 *
 * FLAW 4 (cache_unfriendly_colsum): Iterates over rows in the outer loop
 *   and columns in the inner loop.  R matrices are column-major (Fortran
 *   order), so consecutive elements of a column are contiguous in memory.
 *   Swapping the loop order would give sequential (cache-friendly) access;
 *   the current order strides by nrow bytes between each read, thrashing the
 *   L1/L2 cache on large matrices.  Linux perf will show a high
 *   cache-miss rate; the fast version cuts runtime dramatically.
 *
 * FLAW 5 (leaky_matmul): Naive O(n^3) triple-loop — no blocking / tiling.
 * FLAW 6 (leaky_matmul): Result assembled in a malloc'd buffer that is
 *   never freed — Valgrind reports it as "definitely lost".
 */

#include <R.h>
#include <Rinternals.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ */
SEXP cache_unfriendly_colsum(SEXP mat_)
{
    SEXP dim  = getAttrib(mat_, R_DimSymbol);
    int  nrow = INTEGER(dim)[0];
    int  ncol = INTEGER(dim)[1];
    double *mat = REAL(mat_);

    SEXP result = PROTECT(allocVector(REALSXP, ncol));
    double *out = REAL(result);
    for (int j = 0; j < ncol; j++) out[j] = 0.0;

    /* FLAW 4: outer=row, inner=col — access pattern mat[i + j*nrow] jumps
     * by nrow doubles between consecutive inner iterations. */
    for (int i = 0; i < nrow; i++) {
        for (int j = 0; j < ncol; j++) {
            out[j] += mat[i + j * nrow];   /* stride = nrow — cache miss */
        }
    }

    UNPROTECT(1);
    return result;
}

/* ------------------------------------------------------------------ */
SEXP leaky_matmul(SEXP A_, SEXP B_)
{
    SEXP dimA = getAttrib(A_, R_DimSymbol);
    SEXP dimB = getAttrib(B_, R_DimSymbol);
    int m  = INTEGER(dimA)[0];
    int k  = INTEGER(dimA)[1];
    int k2 = INTEGER(dimB)[0];
    int n  = INTEGER(dimB)[1];

    if (k != k2) error("leaky_matmul: non-conformable matrices (%d vs %d)", k, k2);

    double *A = REAL(A_);
    double *B = REAL(B_);

    /* FLAW 6: temporary result buffer — never freed */
    double *tmp = (double *) malloc((size_t)m * n * sizeof(double));
    if (!tmp) error("leaky_matmul: malloc failed");
    memset(tmp, 0, (size_t)m * n * sizeof(double));

    /* FLAW 5: naive O(m*k*n) triple loop, no cache tiling */
    for (int i = 0; i < m; i++) {
        for (int j = 0; j < n; j++) {
            for (int l = 0; l < k; l++) {
                tmp[i + j * m] += A[i + l * m] * B[l + j * k];
            }
        }
    }

    SEXP result = PROTECT(allocMatrix(REALSXP, m, n));
    double *out = REAL(result);
    memcpy(out, tmp, (size_t)m * n * sizeof(double));

    /* BUG: free(tmp) intentionally omitted */

    UNPROTECT(1);
    return result;
}
