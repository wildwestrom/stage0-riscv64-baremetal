# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

This project explores bootstrapping a computing system **without C** in the bootstrap chain.

The premise: C (like assembly) is fundamentally unsound. Every existing bootstrappable toolchain makes C an integral part of the process. This project aims to create a new chain with a simpler, more rigorously specified language - something with a 10-page specification instead of 600 pages, potentially something formally verified.

The challenge is that doing so requires carving out a system incompatible with everything else:

- No compatibility with existing software (everything relies on C somewhere)
- No compatibility with firmware interfaces (C ABI)
- No ability to run on existing operating systems (C ABI/POSIX)

Despite the incompatibility, this is worthwhile to establish new foundations where safety and correctness are built in from the ground up rather than mitigated after the fact.

## Current Status

The bootstrap chain is functional through hex2:
- **hex0**: Minimal hex loader - reads hex bytes, stores in memory, executes on Ctrl-D
- **hex1**: hex0 + single-character labels (`:x` to define, `@x` for branches, `$x` for jumps, `~x` for U-format, `!x` for I-format)
- **hex2**: hex1 + multi-character labels (`:label_name`), relative pointers (`%label`, `&label`), word literals (`.XXXXXXXX`), alignment padding (`<`)

Working chain: `hex0.bin → hex0.hex0 → hex1.hex0 → hex2.hex1 → program.hex2`

## Development

Tests are automated with `make`. QEMU is used for testing since there's no physical RISC-V machine available.

**Always use `make` targets - never write shell commands by hand.** If a command you need isn't in the Makefile, add it as a new target.

Available test targets:
- `make test_echo` - test the echo program
- `make test_hex0` - test hex0 built from assembly
- `make test_hex0_handwritten` - test hex0 built from hex0.hex0
- `make test_hex1` - test hex1 through full bootstrap chain (hex0.bin → hex0.hex0 → hex1.hex0 → echo.hex1)
- `make test_hex2` - test hex2 through full bootstrap chain (hex0.bin → hex0.hex0 → hex1.hex0 → hex2.hex1 → echo.hex2)
- `make test_m0` - test M0 macro assembler through full bootstrap chain
- `make verify_hex0` - verify hex0.hex0 matches assembly output

### Working with Claude Code

When debugging or investigating issues:

- Always read relevant files and run commands to understand the actual state before making suggestions
- Don't guess or assume - verify with the files and tools in the project

### hex0 File Formatting

hex0 files follow the original stage0 project style (see https://github.com/oriansj/stage0-posix-riscv64):

- `##` for copyright/license header
- `#` for description comments and section headers
- `# label:` for labels on their own line
- `XX XX XX XX       # instruction` - hex bytes left-aligned, then `#` comment with instruction
- `;` only for register usage blocks at the top
- Use base instructions in comments, not pseudo-instructions (e.g., `addi a0, x0, 0` not `li a0, 0`)
- Use hex for ASCII values in comments (e.g., `0x23` not `35` or `'#'`)

Example:
```
# label:
# Description of what this section does
17 31 00 00       # auipc sp, 0x3
13 01 01 18       # addi sp, sp, 384
```

After editing hex0 files, verify with `make verify_hex0`.

### Disassembling for Reference

To get assembly reference from a .s file:

```sh
riscv64-none-elf-as -march=rv64i -mabi=lp64 uart_echo/echo.s -o build/echo.o \
&& riscv64-none-elf-gcc -Ttext=0x80000000 -e _start -march=rv64i -mabi=lp64 \
-mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none \
build/echo.o -o build/echo.elf \
&& riscv64-none-elf-objdump -d build/echo.elf
```

Note: objdump shows instruction words as big-endian hex (e.g., `00040137`). For hex0 format, reverse the bytes: `00040137` → `37 01 04 00`.
