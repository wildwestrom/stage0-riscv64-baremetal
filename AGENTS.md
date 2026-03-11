# ATTN: Agents

This file provides guidance to LLMs when working with code in this repository. Any time you repeatedly make a mistake or waste time, put it here so you don't do it again.

## Comments

Comments are extremely important. Much of this is opaque machine code and assembly. Comments are critical for both humans and LLMs to understand just what the hell is going on. If at any time a comment misled you or doesn't match what's actually happening to the registers, memory, stack, etc. then rewrite it so it matches. Any lies within the comments serve only to mislead future readers and undermine auditability.

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

Note: `objdump` shows instruction words as big-endian hex (e.g., `00040137`). For hex0 format, reverse the bytes: `00040137` → `37 01 04 00`.

## Debug Harness

There is now an agent-oriented QEMU/GDB harness for DerzForth and the Lisp layer.

Use the `just` recipes instead of reconstructing the workflow by hand:

```sh
just debug_lisp_start
just debug_cmd status
just debug_cmd regs
just debug_cmd break interpreter_execute
just debug_cmd serial-write --text '(quote (1 2))\n'
just debug_cmd continue
just debug_cmd serial-drain
just debug_cmd stop
```

Important details:

- The harness state lives under `build/debug/current/`.
- `debug_lisp_start` builds `build/derzforth.debug.elf`, boots QEMU under GDB, loads `prelude.forth`, `control.forth`, and `lisp.forth`, then interrupts the target so it is Lisp-ready and stopped.
- `just debug_cmd ...` returns one JSON object. Consume that JSON instead of scraping human-oriented terminal output.
- Do not rely on `.gdbinit` for automation. The harness starts GDB explicitly with `--nx --nh --interpreter=mi2`.
- If the session is stale or wedged, run `just debug_cmd stop` and start again.
- The harness currently uses QEMU's GDB stub on localhost TCP internally. In restricted sandboxes that block local sockets, the start command can fail even though it works in a normal local shell.

## Plan Maintenance

`PLAN.md` is the living roadmap for this project. Keep it current as you work:

1. **Update as you go** — PLAN.md should reflect reality, not aspirations from three sessions ago.
2. **Collapse completed phases** — when a phase/task is done, replace its detail with a one-line summary (e.g., `~~Phase 2: Token reader~~ — Done.`). Don't delete entirely; keep the record.
3. **Annotate active work** — when starting a phase, add implementation notes and any deviations from the original plan.
4. **Add new items** — when bugs or new requirements surface, add them under an appropriate section.
5. **Keep "next up" accurate** — the next agent should be able to read PLAN.md and know exactly where to pick up.
6. **Prune stale detail** — completed implementation notes waste context and can mislead. Collapse them.
