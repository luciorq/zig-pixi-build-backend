/* Compiled by zig's bundled clang; zlib.h resolves from the conda host
 * environment through the backend's --search-prefix. */
#include <zlib.h>
#include <string.h>

const char *zlib_version_string(void) { return zlibVersion(); }

/* Compress `input` and return the compressed size, or -1 on failure. */
long compress_size(const char *input) {
    unsigned char dest[1024];
    uLongf dest_len = sizeof(dest);
    uLong src_len = (uLong)strlen(input);
    if (compress(dest, &dest_len, (const unsigned char *)input, src_len) != Z_OK) {
        return -1;
    }
    return (long)dest_len;
}
