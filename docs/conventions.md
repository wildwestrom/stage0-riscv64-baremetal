# Conventions

## Comments

Comments are extremely important. Much of this repository is opaque machine code and assembly. Comments are critical for both humans and LLMs to understand what is happening to registers, memory, and the stack.

If a comment is misleading or does not match what the code actually does, rewrite it so it matches reality. Incorrect comments undermine auditability and will mislead future readers.

## File Extensions

According to the stage0 project, macro assembler source files should use the `.M1` extension:

<https://git.sr.ht/~oriansj/bootstrappable-wiki/blob/wiki/stage0.md>

Stage0 uses file extensions to signal the level of infrastructure required to build a file:

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

Use `just annotate_hex0` and `just annotate_hex1` to generate heavily annotated versions of hex machine code.

These commands validate jump and label addresses and try to break each instruction down byte by byte.

## C Source

C is used for high-level prototypes of programs that will eventually be hand-audited and translated from their assembly output. Because of this, C programs should not be clever, limit macro use, and generate small binaries with obvious control flow.
