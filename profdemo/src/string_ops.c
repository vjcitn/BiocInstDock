/*
 * string_ops.c — quadratic string concatenation with cascading leaks.
 *
 * FLAW 7 (slow_string_join): Joins n strings by allocating a brand-new
 *   buffer on every iteration, copying the accumulated result into it, then
 *   discarding (without freeing) the previous buffer.
 *   Total work: O(sum of lengths * n) — quadratic in n.
 *   Total leaked memory: O(n * average_length) bytes across n-1 leaked
 *   malloc calls, each shown by Valgrind as a separate "definitely lost"
 *   block.
 *
 * FLAW 8 (slow_string_join): The final accumulator buffer is also never
 *   freed after the R string object is constructed from it.
 */

#include <R.h>
#include <Rinternals.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ */
SEXP slow_string_join(SEXP strings_, SEXP sep_)
{
    int         n       = LENGTH(strings_);
    const char *sep     = CHAR(STRING_ELT(sep_, 0));
    int         sep_len = (int) strlen(sep);

    /* Start with a single-byte malloc'd empty string */
    char *accum = (char *) malloc(1);
    if (!accum) error("slow_string_join: malloc failed");
    accum[0]    = '\0';
    int accum_len = 0;

    for (int i = 0; i < n; i++) {
        const char *s      = CHAR(STRING_ELT(strings_, i));
        int         s_len  = (int) strlen(s);
        int         need_sep = (i > 0) ? sep_len : 0;
        int         new_len  = accum_len + need_sep + s_len;

        /* FLAW 7 + 8: allocate new buffer, copy old content + separator +
         * new string, then silently drop the old pointer without free(). */
        char *new_accum = (char *) malloc((size_t)(new_len + 1));
        if (!new_accum) error("slow_string_join: malloc failed");

        memcpy(new_accum, accum, (size_t)accum_len);
        if (i > 0)
            memcpy(new_accum + accum_len, sep, (size_t)sep_len);
        memcpy(new_accum + accum_len + need_sep, s, (size_t)(s_len + 1));

        /* BUG: free(accum) intentionally omitted — previous buffer leaks */
        accum     = new_accum;
        accum_len = new_len;
    }

    SEXP result = PROTECT(mkString(accum));
    /* BUG: free(accum) intentionally omitted — final buffer leaks */

    UNPROTECT(1);
    return result;
}
