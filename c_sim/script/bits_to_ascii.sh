#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <in_bits.bin> <out_text.txt>" >&2
  echo "Converts an ASCII 0/1 bitstream (MSB-first, 8 bits per byte) to plaintext bytes." >&2
  exit 1
fi

in="$1"
out="$2"

if [ ! -f "$in" ]; then
  echo "Error: $in not found" >&2
  exit 2
fi

export LC_ALL=C

python3 - "$in" "$out" << 'PY'
import sys, re
inp, outp = sys.argv[1], sys.argv[2]
raw = open(inp,'rt', encoding='latin1').read()
bits = re.sub(r'[^01]', '', raw)
if not bits:
    sys.stderr.write('Error: no 0/1 bits found in input\n')
    sys.exit(3)
pad = (-len(bits)) % 8
if pad:
    sys.stderr.write(f'Info: padding {pad} zero bit(s) at end to complete a byte.\n')
    bits += '0'*pad
bs = bytearray()
for i in range(0, len(bits), 8):
    bs.append(int(bits[i:i+8], 2))
with open(outp, 'wb') as f:
    f.write(bs)
sys.stderr.write(f'OK: wrote {len(bs)} bytes to {outp}\n')
PY
