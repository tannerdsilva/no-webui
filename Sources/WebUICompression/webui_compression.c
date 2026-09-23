#include <webui_compression.h>

#include <stdlib.h>
#include <string.h>

#include <compression.h>

static uint32_t crc32_of(const uint8_t *data, size_t len) {
	uint32_t crc = 0xFFFFFFFFu;
	for (size_t i = 0; i < len; i++) {
		crc ^= data[i];
		for (int b = 0; b < 8; b++) {
			uint32_t mask = (uint32_t)(-(int32_t)(crc & 1));
			crc = (crc >> 1) ^ (0xEDB88320u & mask);
		}
	}
	return crc ^ 0xFFFFFFFFu;
}

static void put_u32le(uint8_t *p, uint32_t v) {
	p[0] = (uint8_t)(v & 0xFF);
	p[1] = (uint8_t)((v >> 8) & 0xFF);
	p[2] = (uint8_t)((v >> 16) & 0xFF);
	p[3] = (uint8_t)((v >> 24) & 0xFF);
}

uint8_t *webui_gzip_compress(const uint8_t *src, size_t src_len, size_t *out_len) {
	if (!src || src_len == 0 || !out_len) return NULL;

	compression_stream stream;
	if (compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_OK) {
		return NULL;
	}

	/* zlib-wrapped output first (2-byte header, 4-byte adler trailer); the
	   framing is rewritten to gzip at the end. the deflate payload is
	   byte-identical, so this is pure container work. */
	size_t cap = src_len + src_len / 8 + 64;
	uint8_t *raw = (uint8_t *)malloc(cap ? cap : 1);
	if (!raw) { compression_stream_destroy(&stream); return NULL; }

	size_t written = 0;
	size_t consumed = 0;
	int final_chunk = 0;
	compression_status status = COMPRESSION_STATUS_OK;

	while (status == COMPRESSION_STATUS_OK) {
		if (stream.src_size == 0) {
			if (consumed == src_len) {
				stream.src_ptr = NULL;
				stream.src_size = 0;
				final_chunk = 1;
			} else {
				size_t n = src_len - consumed;
				if (n > 1 << 20) n = 1 << 20;
				stream.src_ptr = src + consumed;
				stream.src_size = n;
				consumed += n;
			}
		}
		size_t room = cap - written;
		if (room < 65536) {
			size_t ncap = cap * 2 + 64;
			uint8_t *grown = (uint8_t *)realloc(raw, ncap);
			if (!grown) { free(raw); compression_stream_destroy(&stream); return NULL; }
			raw = grown;
			cap = ncap;
			room = cap - written;
		}
		stream.dst_ptr = raw + written;
		stream.dst_size = room;
		status = compression_stream_process(&stream, final_chunk ? COMPRESSION_STREAM_FINALIZE : 0);
		written += room - stream.dst_size;
	}
	compression_stream_destroy(&stream);
	if (status != COMPRESSION_STATUS_END) { free(raw); return NULL; }

	/* the framework emits raw deflate (no zlib wrapper on this sdk), so the
	   whole buffer is the deflate body; frame it as gzip directly. */
	size_t body = written;
	uint8_t *out = (uint8_t *)malloc(body + 18);
	if (!out) { free(raw); return NULL; }
	out[0] = 0x1F; out[1] = 0x8B; out[2] = 0x08; out[3] = 0x00;
	out[4] = 0; out[5] = 0; out[6] = 0; out[7] = 0;
	out[8] = 0x00; out[9] = 0xFF;
	memcpy(out + 10, raw, body);
	put_u32le(out + 10 + body, crc32_of(src, src_len));
	put_u32le(out + 14 + body, (uint32_t)(src_len & 0xFFFFFFFFu));
	free(raw);
	*out_len = body + 18;
	return out;
}

void webui_gzip_free(uint8_t *p) {
	free(p);
}
