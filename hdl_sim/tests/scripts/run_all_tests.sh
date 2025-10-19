#!/usr/bin/env bash
set -euo pipefail

# Vivado (Windows) launcher called from WSL
VIVADO_BAT="C:\\Xilinx\\Vivado\\2023.2\\bin\\vivado.bat"

# Base dir: this script is in hdl_sim/tests/scripts/
base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Files (WSL paths)
dut_wsl="$base_dir/../feistelCipher128by6.v"
tb_wsl="$base_dir/../feistelCipher128by6_tb.sv"

# Make output dirs
mkdir -p "$base_dir/ciphertext" "$base_dir/roundtrip"

start_idx="0x08"
max_index=32
passed=0
failed=0

for i in $(seq 0 "$max_index"); do
  key_wsl="$base_dir/keys/.privatekey$i"
  pt_wsl="$base_dir/plaintext/plaintext$i.txt"
  [[ -f "$key_wsl" && -f "$pt_wsl" ]] || continue

  ct_wsl="$base_dir/ciphertext/ciphertext$i.bin"
  rt_wsl="$base_dir/roundtrip/roundtrip$i.bin"
  log_wsl="$base_dir/roundtrip/run_$i.log"

  # Convert to Windows paths with forward slashes for safer tokenization
  dut_win=$(wslpath -m "$dut_wsl")
  tb_win=$(wslpath -m "$tb_wsl")
  key_win=$(wslpath -m "$key_wsl")
  pt_win=$(wslpath -m "$pt_wsl")
  ct_win=$(wslpath -m "$ct_wsl")
  rt_win=$(wslpath -m "$rt_wsl")

  # Write per-test TCL and inline xsim 'log_wave' commands
  tcl_wsl="$base_dir/roundtrip/run_$i.tcl"
  wdb_wsl="$base_dir/roundtrip/wave_${i}.wdb"
  wdb_win=$(wslpath -m "$wdb_wsl")
  xsim_tcl_win=$(wslpath -m "$base_dir/roundtrip/run_${i}_xsim.tcl")
  cat > "$tcl_wsl" << EOF
exec xvlog -sv {$dut_win} {$tb_win}
exec xelab feistelCipher128by6_tb -s feistel_tb
# Create an xsim batch Tcl inside this same Vivado Tcl
set xsim_tcl {$xsim_tcl_win}
set fp [open \$xsim_tcl w]
puts \$fp {log_wave -r /*}
puts \$fp {run -all}
puts \$fp {quit -force}
close \$fp
exec xsim feistel_tb -simmode batch -onfinish quit -tclbatch {$xsim_tcl_win} -wdb {$wdb_win} \
  --testplusarg "KEY=$key_win" \
  --testplusarg "PT=$pt_win" \
  --testplusarg "CT=$ct_win" \
  --testplusarg "RT=$rt_win" \
  --testplusarg "START=$start_idx"
quit
EOF

  # Run Vivado in batch (via cmd.exe) and tee output
  set +e
  cmd.exe /c "$VIVADO_BAT -mode batch -source $(wslpath -w "$tcl_wsl")" | tee "$log_wsl"
  rc=${PIPESTATUS[0]}
  set -e

  if grep -q "Self-check PASSED" "$log_wsl"; then
    passed=$((passed+1))
  else
    failed=$((failed+1))
  fi
done

if (( passed==0 && failed==0 )); then
  echo "No matching testcases. Expected keys/.privatekey<i> and plaintext/plaintext<i>.txt"
  exit 2
fi

echo "passed=$passed failed=$failed"
if (( failed>0 )); then exit 1; else exit 0; fi