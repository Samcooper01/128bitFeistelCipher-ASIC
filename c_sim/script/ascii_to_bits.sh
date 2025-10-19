#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <plaintext.txt> <out_bits.bin>" >&2
  echo "Converts ASCII text bytes to an ASCII bitstring of 0/1 (MSB-first, 8 bits per byte, no separators)." >&2
  exit 1
fi

in="$1"
out="$2"

if [ ! -f "$in" ]; then
  echo "Error: $in not found" >&2
  exit 2
fi

# Ensure locale doesn't reinterpret bytes
export LC_ALL=C

# Prefer xxd -b if available (portable and fast). Fallback to Python if not.
if command -v xxd >/dev/null 2>&1; then
  xxd -b -c1 -g1 "$in" \
  | awk '{ if (NF>=2) printf "%s", $2 }' \
  > "$out"
else
  python3 - "$in" "$out" << 'PY'
import sys
inp, outp = sys.argv[1], sys.argv[2]
data = open(inp,'rb').read()
with open(outp,'w') as f:
    f.write(''.join(f'{b:08b}' for b in data))
PY
fi

# Report length in bits and bytes
bits=$(wc -c < "$out" | tr -d '[:space:]')
bytes=$(( (bits + 7) / 8 ))
echo "OK: wrote ${bits} bits (${bytes} bytes source) to $out" >&2
