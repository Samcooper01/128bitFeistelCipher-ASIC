#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <file1> <file2>" >&2
  echo "Compares two files containing bitstrings. Non '0'/'1' characters are ignored." >&2
  exit 1
fi

f1="$1"
f2="$2"

if [ ! -f "$f1" ]; then echo "Error: $f1 not found" >&2; exit 2; fi
if [ ! -f "$f2" ]; then echo "Error: $f2 not found" >&2; exit 3; fi

tmp1="$(mktemp)"
tmp2="$(mktemp)"
trap 'rm -f "$tmp1" "$tmp2"' EXIT

tr -cd '01' < "$f1" > "$tmp1"
tr -cd '01' < "$f2" > "$tmp2"

len1=$(wc -c < "$tmp1" | tr -d '[:space:]')
len2=$(wc -c < "$tmp2" | tr -d '[:space:]')

if cmp -s "$tmp1" "$tmp2"; then
  echo "MATCH: equal bitstrings (length=${len1} bits)"
  exit 0
fi

if [ "$len1" -ne "$len2" ]; then
  if [ "$len1" -gt "$len2" ]; then
    longer="$tmp1"; shorter="$tmp2"; llen="$len1"; slen="$len2"; which="file1";
  else
    longer="$tmp2"; shorter="$tmp1"; llen="$len2"; slen="$len1"; which="file2";
  fi
  tail_bits=$(dd if="$longer" bs=1 skip="$slen" status=none)
  if printf "%s" "$tail_bits" | grep -q '[1]'; then
    echo "MISMATCH: different lengths (file1=${len1} bits, file2=${len2} bits)" >&2
    exit 4
  fi
  tmp_trimmed="$(mktemp)"; trap 'rm -f "$tmp1" "$tmp2" "$tmp_trimmed"' EXIT
  dd if="$longer" bs=1 count="$slen" status=none > "$tmp_trimmed"
  if [ "$which" = "file1" ]; then
    if cmp -s "$tmp_trimmed" "$shorter"; then
      echo "MATCH: equal up to shorter length after trimming trailing zeros from file1 (length=${slen} bits)"
      exit 0
    fi
  else
    if cmp -s "$tmp_trimmed" "$shorter"; then
      echo "MATCH: equal up to shorter length after trimming trailing zeros from file2 (length=${slen} bits)"
      exit 0
    fi
  fi
  echo "MISMATCH: contents differ even after trimming trailing zeros on longer file" >&2
  exit 4
fi

first_diff=$(cmp -l "$tmp1" "$tmp2" | awk 'NR==1{print $1}')
if [ -z "$first_diff" ]; then
  echo "MISMATCH: contents differ but position unknown" >&2
  exit 5
fi
# Position is 1-based byte index; each byte is one bit char
pos=$first_diff
b1=$(dd if="$tmp1" bs=1 skip=$((pos-1)) count=1 status=none)
b2=$(dd if="$tmp2" bs=1 skip=$((pos-1)) count=1 status=none)

echo "MISMATCH: first differing bit at position ${pos} (file1='${b1}', file2='${b2}')" >&2
exit 6
