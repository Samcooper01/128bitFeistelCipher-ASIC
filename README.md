# 128-bit Feistel Cipher (RTL + TB + Batch Runner)

A small educational Feistel cipher core with a modular, self‑checking SystemVerilog testbench and a WSL→Windows Vivado batch script. The goal is to demonstrate end‑to‑end RTL + verification + automation under time constraints.

> Note: The cipher is pedagogical (4‑bit halves, 6 rounds, partial key mixing) and not cryptographically secure. See “Roadmap” for hardening options.

## Layout

- `hdl_sim/feistelCipher128by6.v` — RTL core `tt_um_Samcooper01`
- `hdl_sim/feistelCipher128by6_tb.sv` — self‑checking testbench (tasks, assertions)
- `hdl_sim/tests/keys/.privatekey<i>` — 16‑byte keys (e.g., `.privatekey0`, `.privatekey1`)
- `hdl_sim/tests/plaintext/plaintext<i>.txt` — plaintext bytes (e.g., `plaintext0.txt`)
- `hdl_sim/tests/ciphertext/ciphertext<i>.bin` — generated ciphertext (ASCII ‘0’/‘1’ bitstring)
- `hdl_sim/tests/roundtrip/roundtrip<i>.bin` — decrypt output for round‑trip check
- `hdl_sim/tests/roundtrip/wave_<i>.wdb` — optional waveform DBs (when enabled)
- `hdl_sim/tests/scripts/run_all_tests.sh` — batch runner (WSL shell → Windows Vivado)

## Requirements

- Windows Vivado 2023.2 (other versions likely fine; update paths as needed)
- WSL (Ubuntu or similar) or Git Bash. Script is written for WSL and calls `vivado.bat` via `cmd.exe`.

## How it works (high level)

1. The script enumerates tests by index `i`: key `.privatekey<i>` and plaintext `plaintext<i>.txt`.
2. For each test, it generates a per‑test Tcl that runs `xvlog`/`xelab`/`xsim` with plusargs:
   - `KEY`, `PT`, `CT`, `RT`, `START`
3. The testbench:
   - Loads key and plaintext
   - Runs encrypt pass, then decrypt pass
   - Writes `ciphertext<i>.bin` and `roundtrip<i>.bin`
   - Compares roundtrip output to original plaintext and prints PASS/FAIL
   - Assertions check protocol/behavior (see below)

## Run (WSL)

From your repo root (or from the script directory):

```bash
cd /mnt/c/Users/Sam/Desktop/FeistelCIpher-Silicon/128bitFeistelCipher/hdl_sim/tests/scripts
./run_all_tests.sh
```

- The script converts WSL paths to Windows forward‑slash paths using `wslpath -m` and quotes plusargs so `xsim` sees correct tokens.
- Output artifacts:
  - Logs: `hdl_sim/tests/roundtrip/run_<i>.log`
  - Ciphertext: `hdl_sim/tests/ciphertext/ciphertext<i>.bin`
  - Roundtrip: `hdl_sim/tests/roundtrip/roundtrip<i>.bin`
  - Waveforms (if enabled in the script): `hdl_sim/tests/roundtrip/wave_<i>.wdb`

## Waveforms (optional)

When enabled, the script emits `wave_<i>.wdb` per test.

Open in Vivado GUI:

- File → Open Waveform Database → select `hdl_sim/tests/roundtrip/wave_<i>.wdb`

Signals of interest:

- `clk`, `rst_n`, `ui_in`, `uo_out`, `uio_in[1]` (stop)
- `feistel_out`, `curr_seg`, `local_key` (internal paths), `sys_state` if bound/exported

## Testbench features

- **Tasks**: `tb_reset()`, `tb_set_key()`, `tb_set_start_idx()`, `tb_start_stream()`, `tb_stop_stream()`, `tb_stream_bytes()`, `tb_run_pass()`
- **Self‑check**: compares decrypted round‑trip output to original plaintext; `$fatal` on mismatch
- **Assertions** (selected):
  - **Stream integrity**: mode fixed during stream; no unexpected stop while streaming
  - **Unknowns**: `uo_out` must not be X/Z during stream
  - **Idle behavior**: when fully idle (not streaming and post‑stop grace window elapsed), `uo_out == 8'h00` and known
  - **Stop latency**: allow a 2‑cycle grace window, then require `uo_out == 0`
  - **Key load**: exactly 16 bytes loaded (TB-side counter)

## Troubleshooting

- **Vivado not found**: Ensure `C:\Xilinx\Vivado\2023.2\bin\vivado.bat` exists. Script calls it via `cmd.exe`.
- **Plusarg tokenization**: The script uses forward slashes (`C:/...`) and wraps each plusarg as a single quoted token (e.g., `--testplusarg "KEY=C:/..."`).
- **Batch hang**: The per‑test Tcl uses `-simmode batch -onfinish quit` and an inline Tcl (`log_wave -r /*; run -all; quit -force`). If you disable waveforms, you can switch to `-R` runs.
- **Assertion prints**: If you see first‑byte X during stream, add one clock between `tb_start_stream()` and streaming bytes. If output lingers after stop, widen the grace window.

## Roadmap (hardening + sign‑off)

- **Cipher hardening** (if security is a goal):
  - Full‑byte key mixing per round, S‑box in F, 12–16+ rounds
  - Whitening and inter‑byte diffusion; stronger key schedule
  - Or implement a standard (PRESENT or AES‑128 serial)
- **Verification depth**:
  - Add SVAs bound to DUT state (state-gated checks, stop→idle latency)
  - Functional coverage (bins for `start_idx`, mode, data classes)
- **GLS**:
  - Synthesize to a gate‑level netlist and run the same TB
  - Compare outputs and (optionally) run with SDF timing
- **Docs/CI**:
  - Add a concise CI or Makefile; pin Vivado version in README

## Notes

- This design is intended as a learning/demonstration vehicle, not for production crypto use.
- The batch flow assumes WSL; if you prefer Git Bash, update the path conversions accordingly.

## Results (STA, reg→reg)

- **[corner]** `nom_ff_n40C_1v95`

- **[worst reg→reg path: optimized]** `asic/optimizations/STA_n_POWER/nom_ff_n40C_1v95/max.rpt`
  - Path: `Startpoint: _1050_ (FF)` → `Endpoint: _1036_ (FF)`
  - Data arrival time: `0.838149 ns`

- **[worst reg→reg path: non-optimized]** `asic/no_optimizations/STA_n_POWER/nom_ff_n40C_1v95/max.rpt`
  - Path: `Startpoint: _1147_ (FF)` → `Endpoint: _1145_ (FF)`
  - Data arrival time: `0.926046 ns`

- **[implication]** Based on worst reg→reg data arrival, the optimized build has a shorter internal critical path (~0.84 ns vs ~0.93 ns), i.e., higher core Fmax for reg→reg logic. Use this alongside `report_clock_min_period` and WNS/TNS@fixed period for a complete picture.

## Final RTL configuration

- **[rounds]** Single-cycle 6-round compute in `hdl_sim/feistelCipher128by6_opt.v` (no internal round pipeline).
- **[output pipeline]** 1-cycle register on `feistel_out` with `out_valid` gating; `uo_out = out_valid ? feistel_out_q : 8'h00`.
- **[key]** Key bytes captured into `key_bytes[15-counter]` and selected via `key_bytes[curr_seg]` (avoids variable barrel select).
- **[FSM]** `sys_next_state` defaulted to `sys_state` in the comb next-state block.
- **[operand gating]** Round compute only when `sys_state == SYS_STREAMING`; `feistel_out = 8'h00` otherwise.

## Final Results Summary

- **[corner]** `nom_ff_n40C_1v95`
- **[internal Fmax (period_min)]**
  - Non-optimized: `period_min = 1.47 ns` → ~682.39 MHz (`asic/no_optimizations/.../clock.rpt`)
  - Optimized: `period_min = 5.05 ns` → ~197.88 MHz (`asic/optimizations/.../clock.rpt`)
  - Note: Period_min is an internal reg→reg metric and may appear higher for designs with trivial reg→reg paths. See reg→reg worst-path below for a fairer comparison.
- **[worst reg→reg delay (max.rpt)]**
  - Non-optimized: ~0.926046 ns (`_1147_ → _1145_`)
  - Optimized: ~0.838149 ns (`_1050_ → _1036_`)
- **[power (vectorless)]**
  - Non-optimized total: ~4.213 mW (`asic/no_optimizations/.../power.rpt`)
  - Optimized total: ~6.074 mW (`asic/optimizations/.../power.rpt`)
  - Note: Vectorless power does not reflect operand gating benefits. Use activity-based power for realistic results.

## How to reproduce (concise)

- **[simulation]**
  - Run `hdl_sim/tests/scripts/run_all_tests.sh` (see Run section above). Outputs go to `hdl_sim/tests/{ciphertext,roundtrip}/`.
- **[STA]**
  - Use the provided ASIC flow to generate `clock.rpt`, `max.rpt` in:
    - `asic/no_optimizations/STA_n_POWER/nom_ff_n40C_1v95/`
    - `asic/optimizations/STA_n_POWER/nom_ff_n40C_1v95/`
- **[power (vectorless)]**
  - `report_power` at the same corner produces `power.rpt` in the same folders.
- **[power (activity-based, recommended)]**
  - Dump VCD during sim:
    - SV: add to TB initial: `$dumpfile("wave.vcd"); $dumpvars(0, feistelCipher128by6_tb);`
    - Or XSim Tcl: `open_vcd wave.vcd; log_vcd [get_objects /*]; run -all; close_vcd`
  - Convert to SAIF (if needed): `vcd2saif -input wave.vcd -output activity.saif -instance feistelCipher128by6_tb.iDUT`
  - Re-run `report_power` with SAIF for both builds; save as `power_saif.rpt` in each folder.

## Submission Notes

- The repository includes:
  - **RTL/TB** with self-checking flow and assertions.
  - **Reports** for timing and power at `nom_ff_n40C_1v95` for both variants.
  - **README** documenting methodology, metrics, and reproduction steps.
- If desired, add a small table in this section capturing your final numbers (period_min, worst reg→reg delay, power) when you freeze the run.
