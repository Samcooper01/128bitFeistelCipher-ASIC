#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

typedef enum {
 STATE_IDLE = 0,
 STATE_KEY_LOAD = 1,
 STATE_KEYGEN_CFG = 2,
 STATE_STREAM = 3
} fc_state_t;

static uint8_t g_key[16];
static uint8_t g_key_loaded;
static uint8_t g_keygen_start;
static uint8_t g_keygen_set;
static uint8_t g_keygen_pos;
static fc_state_t g_state;
static uint8_t g_key_load_count;
static uint8_t g_stream_in_count;
static uint8_t g_stream_out_count;
static uint8_t g_stream_in_buf[16];
static uint8_t g_stream_out_buf[16];
static uint8_t g_stream_out_buf2[16];
static bool g_out_buf_valid;
static bool g_out_buf2_valid;
static bool g_expect_keygen_index;

static inline uint8_t rotl4(uint8_t x)
{
  return (uint8_t)(((x << 1) | (x >> 3)) & 0x0F);
}

// RTL-matching: process a single byte through 6 rounds on nibbles
static uint8_t feistel_encrypt_byte(uint8_t in_b, uint8_t key_b, uint8_t start_idx)
{
  // Use plaintext byte as Feistel input (prior behavior)
  uint8_t L = (uint8_t)(in_b >> 4) & 0x0F;
  uint8_t R = (uint8_t)(in_b & 0x0F);
  uint8_t key_hi = (uint8_t)((key_b >> 4) & 0x0F);
  for (int r = 0; r < 6; ++r) {
    uint8_t K = (uint8_t)(((start_idx & 0x0F) + (uint8_t)r) & 0x0F);
    K ^= key_hi;
    uint8_t F = (uint8_t)((((uint8_t)(R + K)) & 0x0F) ^ rotl4(R));
    uint8_t newL = R;
    uint8_t newR = (uint8_t)((L ^ F) & 0x0F);
    L = newL;
    R = newR;
  }
  uint8_t out_b = (uint8_t)(((L & 0x0F) << 4) | (R & 0x0F));
  return out_b;
}

static uint8_t feistel_decrypt_byte(uint8_t in_b, uint8_t key_b, uint8_t start_idx)
{
  // Standard Feistel inverse: iterate rounds in reverse, compute F on current L
  // Use ciphertext byte as Feistel input for inverse (prior behavior)
  uint8_t L = (uint8_t)(in_b >> 4) & 0x0F;
  uint8_t R = (uint8_t)(in_b & 0x0F);
  uint8_t key_hi = (uint8_t)((key_b >> 4) & 0x0F);
  for (int r = 5; r >= 0; --r) {
    uint8_t K = (uint8_t)(((start_idx & 0x0F) + (uint8_t)r) & 0x0F);
    K ^= key_hi;
    uint8_t F = (uint8_t)((((uint8_t)(L + K)) & 0x0F) ^ rotl4(L));
    uint8_t newR = L;
    uint8_t newL = (uint8_t)((R ^ F) & 0x0F);
    L = newL;
    R = newR;
  }
  uint8_t out_b = (uint8_t)(((L & 0x0F) << 4) | (R & 0x0F));
  return out_b;
}

void fc128_reset(int rst_n)
{
 if (!rst_n) {
   memset(g_key, 0, sizeof(g_key));
   g_key_loaded = 0;
   g_keygen_start = 0;
   g_keygen_set = 0;
   g_keygen_pos = 0;
   g_state = STATE_IDLE;
   g_key_load_count = 0;
   g_stream_in_count = 0;
   g_stream_out_count = 0;
   memset(g_stream_in_buf, 0, sizeof(g_stream_in_buf));
   memset(g_stream_out_buf, 0, sizeof(g_stream_out_buf));
   memset(g_stream_out_buf2, 0, sizeof(g_stream_out_buf2));
   g_out_buf_valid = false;
   g_out_buf2_valid = false;
   g_expect_keygen_index = false;
 }
}

void fc128_process_byte(uint8_t in_byte, uint8_t* out_byte, int* out_valid)
{
 *out_valid = 0;
 if (g_state == STATE_IDLE) {
   if (in_byte == 0x01) {
     g_state = STATE_KEY_LOAD;
     g_key_load_count = 0;
   } else if (in_byte == 0x0f) {
     g_state = STATE_KEYGEN_CFG;
     g_expect_keygen_index = true;
   } else if (in_byte == 0x02) {
     g_state = STATE_STREAM;
     g_stream_in_count = 0;
     g_stream_out_count = 0;
     g_out_buf_valid = false;
     g_out_buf2_valid = false;
   }
   return;
 }

 if (g_state == STATE_KEY_LOAD) {
   if (g_key_load_count < 16) {
     g_key[g_key_load_count++] = in_byte;
     if (g_key_load_count == 16) {
       g_key_loaded = 1;
       g_state = STATE_IDLE;
     }
   }
   return;
 }

 if (g_state == STATE_KEYGEN_CFG) {
   if (g_expect_keygen_index) {
     g_keygen_start = in_byte;
     g_keygen_set = 1;
     g_keygen_pos = (uint8_t)(g_keygen_start & 0x0F);
     g_expect_keygen_index = false;
     g_state = STATE_IDLE;
   }
   return;
 }

 if (g_state == STATE_STREAM) {
   if (in_byte == 0x03) {
     g_state = STATE_IDLE;
     g_stream_in_count = 0;
     g_stream_out_count = 0;
     g_out_buf_valid = false;
     g_out_buf2_valid = false;
     return;
   }
   g_stream_in_buf[g_stream_in_count++] = in_byte;
   if (g_stream_in_count == 16) {
     // Process 16 bytes in-place using RTL-like per-byte cipher, advancing key index by 1 per byte
    for (int i = 0; i < 16; ++i) {
      uint8_t key_b = g_key[(uint8_t)(g_keygen_pos & 0x0F)];
      g_stream_out_buf[i] = feistel_encrypt_byte(g_stream_in_buf[i], key_b, g_keygen_start);
      g_keygen_pos = (uint8_t)((g_keygen_pos + 1) & 0x0F);
    }
    g_out_buf_valid = true;
    g_stream_out_count = 0;
     g_stream_in_count = 0;
   }
   if (g_out_buf_valid) {
     *out_byte = g_stream_out_buf[g_stream_out_count++];
     *out_valid = 1;
     if (g_stream_out_count == 16) {
       g_out_buf_valid = false;
       g_stream_out_count = 0;
     }
   }
   return;
 }
}

static int load_key_from_file(const char* path)
{
 FILE* f = fopen(path, "rb");
 if (!f) return -1;
 uint8_t buf[512];
 size_t n = fread(buf, 1, sizeof(buf), f);
 fclose(f);
 if (n == 16) {
   memcpy(g_key, buf, 16);
   g_key_loaded = 1;
   return 0;
 }
 size_t bitcount = 0;
 for (size_t i = 0; i < n && bitcount < 128; ++i) {
   if (buf[i] == '0' || buf[i] == '1') bitcount++;
 }
 if (bitcount < 128) return -2;
 size_t idx = 0;
 for (int b = 0; b < 16; ++b) g_key[b] = 0;
 for (size_t i = 0, collected = 0; i < n && collected < 128; ++i) {
   if (buf[i] != '0' && buf[i] != '1') continue;
   uint8_t bit = (uint8_t)(buf[i] == '1');
   size_t byte_index = collected / 8;
   size_t bit_in_byte = 7 - (collected % 8);
   g_key[byte_index] |= (uint8_t)(bit << bit_in_byte);
   collected++;
 }
 g_key_loaded = 1;
 return 0;
}

static void set_keygen_start_idx(uint8_t idx)
{
 g_keygen_start = idx;
 g_keygen_set = 1;
 g_keygen_pos = (uint8_t)(idx & 0x0F);
}

static int read_bits_file(const char* path, uint8_t** bytes_out, size_t* len_bytes_out)
{
 FILE* f = fopen(path, "rb");
 if (!f) return -1;
 fseek(f, 0, SEEK_END);
 long sz = ftell(f);
 if (sz < 0) { fclose(f); return -2; }
 fseek(f, 0, SEEK_SET);
 uint8_t* buf = (uint8_t*)malloc((size_t)sz);
 if (!buf) { fclose(f); return -3; }
 size_t n = fread(buf, 1, (size_t)sz, f);
 fclose(f);
 size_t bitcount = 0;
 for (size_t i = 0; i < n; ++i) if (buf[i] == '0' || buf[i] == '1') bitcount++;
 if (bitcount == 0) { free(buf); return -4; }
 size_t out_bytes = (bitcount + 7) / 8;
 uint8_t* out = (uint8_t*)malloc(out_bytes);
 if (!out) { free(buf); return -5; }
 for (size_t b = 0; b < out_bytes; ++b) out[b] = 0;
 size_t collected = 0;
 for (size_t i = 0; i < n && collected < bitcount; ++i) {
   if (buf[i] != '0' && buf[i] != '1') continue;
   uint8_t bit = (uint8_t)(buf[i] == '1');
   size_t byte_index = collected / 8;
   size_t bit_in_byte = 7 - (collected % 8);
   out[byte_index] |= (uint8_t)(bit << bit_in_byte);
   collected++;
 }
 free(buf);
 *bytes_out = out;
 *len_bytes_out = out_bytes;
 return 0;
}

static int write_bits_file(const char* path, const uint8_t* data, size_t len_bytes)
{
 FILE* f = fopen(path, "wb");
 if (!f) return -1;
 for (size_t i = 0; i < len_bytes; ++i) {
  for (int b = 7; b >= 0; --b) {
    char c = ((data[i] >> b) & 1) ? '1' : '0';
    if (fputc(c, f) == EOF) { fclose(f); return -2; }
  }
 }
 fclose(f);
 return 0;
}

static void print_usage(const char* prog)
{
 fprintf(stderr, "Usage: %s <enc|encrypt|dec|decrypt> <in_bits.bin> <out_bits.bin> <key_start_idx>\n", prog);
 fprintf(stderr, "  Key: .privatekey (16 raw bytes or 128 '0'/'1' chars).\n");
 fprintf(stderr, "  Input/Output: ASCII '0'/'1' bitstrings, length must be multiple of 128.\n");
 fprintf(stderr, "  Example: %s enc plaintext.bin ciphertext.bin 0x00\n", prog);
 fprintf(stderr, "           %s dec ciphertext.bin roundtrip.bin 0x00\n", prog);
}

int main(int argc, char** argv)
{
 if (argc == 2 && (!strcmp(argv[1], "-h") || !strcmp(argv[1], "--help"))) { print_usage(argv[0]); return 0; }
 if (argc != 5) { print_usage(argv[0]); return 1; }
 const char* mode = argv[1];
 const char* in_path = argv[2];
 const char* out_path = argv[3];
 unsigned long idx = strtoul(argv[4], NULL, 0);
 if (idx > 255) { fprintf(stderr, "Error: key_start_idx out of range (0-255).\n"); return 2; }
 if (load_key_from_file(".privatekey") != 0) { fprintf(stderr, "Error: failed to load .privatekey (expect 16 raw bytes or 128 '0'/'1').\n"); return 3; }
 set_keygen_start_idx((uint8_t)idx);
 uint8_t* in_bytes = NULL;
 size_t in_len = 0;
 if (read_bits_file(in_path, &in_bytes, &in_len) != 0) { fprintf(stderr, "Error: input must be ASCII '0'/'1' (bit length > 0).\n"); return 4; }
 // Do not pad: process exactly the input length
 size_t out_len = in_len;
 uint8_t* out_bytes = (uint8_t*)malloc(out_len);
 if (!out_bytes) { free(in_bytes); fprintf(stderr, "Error: allocation failed for output.\n"); return 6; }
 for (size_t off = 0; off < out_len; ++off) {
    uint8_t pos = (uint8_t)(g_keygen_pos & 0x0F);
    uint8_t key_b = g_key[pos];
    if (strcmp(mode, "enc") == 0 || strcmp(mode, "encrypt") == 0) {
      out_bytes[off] = feistel_encrypt_byte(in_bytes[off], key_b, g_keygen_start);
    } else if (strcmp(mode, "dec") == 0 || strcmp(mode, "decrypt") == 0) {
      out_bytes[off] = feistel_decrypt_byte(in_bytes[off], key_b, g_keygen_start);
      if (off < 10) {
        fprintf(stderr,
          "dec[%zu]: key=%02X data=%02X out=%02X start=%u key_pos=%u\n",
          off,
          key_b,
          in_bytes[off],
          out_bytes[off],
          (unsigned)g_keygen_start,
          (unsigned)pos);
      }
    } else { free(in_bytes); free(out_bytes); fprintf(stderr, "Error: mode must be enc|encrypt|dec|decrypt.\n"); return 7; }
    g_keygen_pos = (uint8_t)((g_keygen_pos + 1) & 0x0F);
  }
 int wrc = write_bits_file(out_path, out_bytes, out_len);
  free(in_bytes);
  free(out_bytes);
  if (wrc != 0) { fprintf(stderr, "Error: failed to write output file.\n"); return 8; }
 fprintf(stderr, "OK: processed %zu bits across %zu bytes.\n", out_len * 8ULL, out_len);
  return 0;
}
