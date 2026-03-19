# Reference Material

## Purpose

The `reference/` directory contains a large amount of useful background material for this repository. It is not part of the main implementation, but it often contains the fastest route to understanding an instruction encoding, ABI rule, calling convention, stage0 convention, or prior-art implementation detail.

Treat it as a high-value research library.

## How To Use It

Do not read the entire `reference/` tree by default. It is large enough to waste time and context.

Instead:

1. Use `tree -L 2 reference` or `rg --files reference` to discover the relevant area.
2. Open only the files that match the current task.
3. Prefer the reference material when you need to verify semantics, encodings, conventions, or historical stage0 behavior.

For ordinary repository discovery, `tree --gitignore -I reference` is still useful because it keeps the project layout readable. When a task depends on external context or prior art, inspect `reference/` directly.

## What Is In There

Current high-value areas include:

- `reference/original_stage0/`
  - Upstream stage0 source and notes. Useful for naming, conventions, historical behavior, and implementation reference.
- `reference/riscv-opcodes/`
  - Opcode and encoding reference material. Useful when checking instruction formats and operand encodings.
- `reference/riscv-tests/`
  - RISC-V test material and examples. Useful for understanding expected ISA behavior and test patterns.
- `reference/binutils-gdb/`
  - The most important is the the `gas` implementation. Useful for inspiration when creating assemblers.
- `reference/fasm/`
  - An assembler written in pure x86_64 assembly. Useful for inspiration when creating assemblers and macro systems for assembly.
- Top-level markdown files such as:
  - `reference/RISC-V_Calling_Conventions.md`
  - `reference/CHERI-RISC-V_ELF_psABI_Extensions.md`
  - `reference/CHERI Instruction-Set Architecture (Version 9).md`
  - `reference/ABI_design_research.md`
  - These are useful when ABI, calling convention, CHERI, or design questions come up.

## When To Consult It

Check `reference/` when:

- an instruction encoding or operand layout is unclear
- a calling convention or ABI detail matters
- you need prior art from stage0 or related bootstrap tooling
- you need examples of tests or expected ISA behavior
- the repository code is too low-level or sparse to explain itself fully

If a task touches architectural semantics, `reference/` is often more authoritative than guessing from the local implementation.
