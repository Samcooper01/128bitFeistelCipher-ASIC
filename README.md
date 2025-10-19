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
