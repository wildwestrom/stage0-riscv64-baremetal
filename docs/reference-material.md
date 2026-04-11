# Reference Material

## Purpose

`reference/` dir: large background material. Not main impl, but fastest route to instruction encoding, ABI rules, calling conventions, stage0 conventions, prior-art details.

Treat as high-value research library.

## How To Use It

Don't read entire `reference/` tree. Too large.

Instead:

1. Use `tree -L 2 reference` or `rg --files reference` to find relevant area.
2. Open only files matching current task.
3. Prefer reference material to verify semantics, encodings, conventions, historical stage0 behavior.

For ordinary repo discovery, `tree --gitignore -I reference` keeps project layout readable. Task needs external context or prior art → inspect `reference/` directly.

## What Is In There

High-value areas:

- `reference/original_stage0/`
  - Upstream stage0 source/notes. Naming, conventions, historical behavior, impl reference.
- `reference/riscv-opcodes/`
  - Opcode/encoding reference. Check instruction formats and operand encodings.
- `reference/riscv-tests/`
  - RISC-V test material. Expected ISA behavior and test patterns.
- `reference/binutils-gdb/`
  - Key: `gas` impl. Assembler inspiration.
- `reference/fasm/`
  - Assembler in pure x86_64 asm. Assembler/macro system inspiration.
- Top-level markdown files:
  - `reference/RISC-V_Calling_Conventions.md`
  - `reference/CHERI-RISC-V_ELF_psABI_Extensions.md`
  - `reference/CHERI Instruction-Set Architecture (Version 9).md`
  - `reference/ABI_design_research.md`
  - ABI, calling convention, CHERI, design questions.

## When To Consult It

Check `reference/` when:

- instruction encoding or operand layout unclear
- calling convention or ABI detail matters
- need prior art from stage0 or bootstrap tooling
- need test examples or expected ISA behavior
- repo code too low-level/sparse to explain itself

Task touches architectural semantics → `reference/` more authoritative than guessing from local impl.