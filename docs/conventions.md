# Conventions

## Comments

Comments critical. Repo full of opaque machine code/assembly. Comments needed for humans+LLMs to understand registers, memory, stack.

Misleading/wrong comments: rewrite to match reality. Wrong comments break auditability, mislead future readers.

## File Extensions

stage0 project: macro assembler source uses `.M1` extension:

<https://git.sr.ht/~oriansj/bootstrappable-wiki/blob/wiki/stage0.md>

Stage0 file extensions signal infrastructure level needed to build:

> File extensions are very important in stage0, they directly indicate the level of infrastructure
> required to build them.
>
> * HEX0 - indicates that the file can be built using the stage0 hex monitor or any other tool that supports the minimal commented hex syntax
> * HEX1 - indicates that the file also requires support for 1 character labels and a single size (commonly 16bit) relative displacements.
> * HEX2 - indicates that the file also requires support for long labels, 16bit absolute displacements and 32bit pointers for manual object creation.
> * M0/M1/S - indicates that the file can either be built by the platform specific M0 macro assembler or the platform neutral M1 macro assembler
> * c/h - indicates that the file contains C code
> * s/inc - indicates that the file contains assembly (in this project we have to use GNU assembler as it's the only one that supports our target)

## Annotated Hex

Use `just annotate_hex0` and `just annotate_hex1` for heavily annotated hex machine code versions.

Commands validate jump/label addresses, break instructions byte-by-byte.

## C Source

C = high-level prototypes, later hand-audited and translated from assembly output. C code: no cleverness, minimal macros, small binaries, obvious control flow.