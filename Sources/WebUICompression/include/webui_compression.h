#ifndef WEBUI_COMPRESSION_H
#define WEBUI_COMPRESSION_H

#include <stddef.h>
#include <stdint.h>

/// gzip (rfc-1952) compress `src` into a malloc'd buffer; on success returns
/// the buffer and sets `out_len`; caller frees with `webui_gzip_free`.
/// returns NULL on failure or empty input.
uint8_t *webui_gzip_compress(const uint8_t *src, size_t src_len, size_t *out_len);

void webui_gzip_free(uint8_t *p);

#endif
