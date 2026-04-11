# Workflows

## Jujutsu Enchanced Version Control

Jujutsu available for tracking/undoing/reordering changes.
No `git`; translate to `jj` equivalent.

**Never use `jj restore`** on files user actively edits. Discards in-progress work. To revert modified file, ask user approval.

## Automated Testing And Builds

Tests automated with `just`. QEMU used for testing; no physical RISC-V available.

Use `just` recipes over ad hoc shell commands. Missing needed command + complex enough to reuse/get wrong → add new recipe.

Canonical merge-gating test: `just test`. Secondary compatibility check: `just test_as0_riscv_tests`.

`scripts/generate_as0_m1.py`: keep off normal `just` surface. Last-resort analysis/regeneration aid for `baremetal/as0.M1` only.

## Discovery

Use `tree` for repo structure. Preferred form:

```sh
tree --gitignore -I reference
```

## Disassembling For Reference

Assembly reference from `.s` file:

```sh
riscv64-none-elf-as -march=rv64im -mabi=lp64 uart_echo/echo.s -o build/echo.o \
&& riscv64-none-elf-gcc -Ttext=0x80000000 -e _start -march=rv64im -mabi=lp64 \
-mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none \
build/echo.o -o build/echo.elf \
&& riscv64-none-elf-objdump -d build/echo.elf
```

`objdump` shows instruction words as big-endian hex, e.g. `00040137`. hex0 format: reverse bytes → `37 01 04 00`.