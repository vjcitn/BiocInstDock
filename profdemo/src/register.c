/*
 * register.c — registers all native routines so R can find them by name
 * without requiring dynamic symbol resolution (R_useDynamicSymbols = FALSE).
 */

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

extern SEXP slow_sort(SEXP);
extern SEXP slow_cumsum(SEXP);
extern SEXP cache_unfriendly_colsum(SEXP);
extern SEXP leaky_matmul(SEXP, SEXP);
extern SEXP slow_string_join(SEXP, SEXP);

static const R_CallMethodDef CallEntries[] = {
    {"slow_sort",               (DL_FUNC) &slow_sort,               1},
    {"slow_cumsum",             (DL_FUNC) &slow_cumsum,             1},
    {"cache_unfriendly_colsum", (DL_FUNC) &cache_unfriendly_colsum, 1},
    {"leaky_matmul",            (DL_FUNC) &leaky_matmul,            2},
    {"slow_string_join",        (DL_FUNC) &slow_string_join,        2},
    {NULL, NULL, 0}
};

void R_init_profdemo(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
}
