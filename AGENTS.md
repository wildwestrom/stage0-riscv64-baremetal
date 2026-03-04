# ATTN: Agents

This file provides guidance to LLMs when working with code in this repository. Any time you repeatedly make a mistake or waste time, put it here so you don't do it again.

## Automated Testing

Tests are automated with `just`. QEMU is used for testing since there's no physical RISC-V machine available.

**Use `just` recipes - avoid writing shell commands by hand.** If a command you need isn't in the `justfile` and it's complicated, add it as a new recipe. It's much less error-prone and saves on context. I can always clear the context once we get a working command.

## Discovery

The `tree` command is useful for discovering files within the project and understanding its current structure. Also use `tree --gitignore` for less noisy output.

## What is with the weird file extensions?
According to the stage0 project (https://git.sr.ht/~oriansj/bootstrappable-wiki/blob/wiki/
  stage0.md) the macro assembler source files should all have the extension `.M1`.

> File extensions are very important in stage0, they directly indicate the level of infrastructure
> required to build them.
> * HEX0 - indicates that the file can be built using the stage0 hex monitor or any other tool
> that supports the minimal commented hex syntax
> * HEX1 - indicates that the file also requires support for 1 character labels and a single size
> (commonly 16bit) relative displacements.
> * HEX2 - indicates that the file also requires support for long labels, 16bit absolute
> displacements and 32bit pointers for manual object creation.
> * M0/M1/S - indicates that the file can either be built by the platform specific M0 macro
> assembler or the platform neutral M1 macro assembler
> * c/h - indicates that the file contains C code

## Disassembling for Reference

To get assembly reference from a .s file, roughly do this:

```sh
riscv64-none-elf-as -march=rv64i -mabi=lp64 uart_echo/echo.s -o build/echo.o \
&& riscv64-none-elf-gcc -Ttext=0x80000000 -e _start -march=rv64i -mabi=lp64 \
-mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none \
build/echo.o -o build/echo.elf \
&& riscv64-none-elf-objdump -d build/echo.elf
```

Note: objdump shows instruction words as big-endian hex (e.g., `00040137`). For hex0 format, reverse the bytes: `00040137` → `37 01 04 00`.
