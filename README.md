# Stage-0 but without C

> **Archived.** This repository is not under active development. What remains is a working RISC-V bare-metal bootstrap experiment and the notes around it — not a foundation to trust or extend.

From machine code toward a compiler without intermediate C. That was the goal.

The master repository is on <https://github.com/wildwestrom/stage0-riscv64-baremetal>.

## Status (read this first)

This project stopped short of its original ambition. It is **not**:

1. **A trust artifact.** Much of the work was LLM-authored. I personally audited the early seeds (`hex0`, `hex1`) in the stage0 sense — full human read-through of every instruction — but that is *my* audit, not a multi-reviewer public process, and later stages were not audited the same way. None of this is enough for binary provenance, a shared root-of-trust, or "trusting trust" claims others should rely on. Treat the chain as experiment output unless you re-audit it yourself.
2. **A proof.** An audited (or self-hosting) bootstrap is not formal verification. Reaching a fixed point — the chain builds itself and the bits match — is a useful engineering property and nothing more. There are no correctness theorems, no machine-checked semantics, and no guarantees beyond "it compiled to a fixed point on the paths that were tested."

What *is* here: a QEMU-tested bare-metal chain `hex0 → hex1 → hex2 → M0` (plus an `as0` assembler start), following the stage0 philosophy but refusing intermediate C. The interesting research question that motivated this — correct foundations for systems software without C in the trust path — is better pursued by integrating existing verified pipelines (CakeML/Pancake, Bedrock2, Jasmin, …) than by growing another hand-written hex tower. My current thinking on that problem is in a separate survey on proof-carrying systems software; this repo is historical context, not that answer.

---

# Wait, what?

To those who already know what bootstrapping is, skip to the next section.

>	Do you know how to make yoghurt? The first step is to add yoghurt to milk! How can you build a compiler like GCC? The first step is to get a compiler that can compile the compiler.
> — [bootstrappable.org](https://bootstrappable.org/)

So where do you get your C compiler from? Do you download it from Microsoft's website? Do you get it from your Linux package repository? Does one come pre-installed on your computer?

There are many ways to get a compiler. Once you have a compiler you can build another compiler! This is the way most compilers are developed, both old and new. However you see there's a chicken and egg problem, right? Where did the first compiler come from? Bootstrapping is the process of creating the toolchain that builds the first compiler and every compiler after that.

## Why

Software sucks. It's buggy, unreliable, and slow. Why do we put up with this? More importantly, what's the cause?

In fact, there are many causes. This experiment tackled just one: the abstractions we all build on top of. C works great as a portable assembler, but can you guarantee anything about its behavior? Are you sure there are no stack smashing or off-by-one edge-cases? Would you run your C on the Therac-25? An F-35 fighter jet? Maybe you program like NASA and follow strict discipline for correctness. Best case scenario, you run your C code through CompCert C and get a guarantee that your code follows C's ill-defined semantics exactly.

Enough! Let's start from 0. Stage 0 to be exact. This project was heavily inspired by [oriansj/stage0](https://github.com/oriansj/stage0) and [live-bootstrap](https://github.com/fosslinux/live-bootstrap/blob/master/parts.rst). I knew this was the direction I wanted to go, but why the hell are there 80+ steps to get an old version of GCC?

## The Approach

This project follows the [`stage0`](https://github.com/oriansj/stage0) bootstrap philosophy: Start from hex, build up through progressively more capable assemblers, but diverges after the macro assembler stage. Where `stage0` builds toward C, we don't.

**Original goal** was a path toward a formally verified, correctness-oriented compiler without accepting C (`cc_x86`, `M2 Planet`, `mescc`, `tinycc`) as an intermediate foundation. Accepting C at any point means accepting its ill-defined semantics as part of the base. The open questions this was meant to force were:

- What are the right semantics for a correctness-first language?
- How do we build up to such a language?

Those questions still matter. Building another stage0-style tower turned out to be the wrong vehicle for answering them; see [Status](#status-read-this-first).

## Where We're At

The bootstrap chain has been tested on QEMU.

The full chain:

```
hex0 → hex1 → hex2 → M0
```

See also: [git.sr.ht/~oriansj/bootstrappable-wiki/tree/wiki/item/stage0.md](https://git.sr.ht/~oriansj/bootstrappable-wiki/tree/wiki/item/stage0.md) — What is with the weird file extensions?

**Assembler stages:**

- **hex0**: Minimal hex loader — reads hex bytes from UART, stores in memory, executes on sending Ctrl-D
- **hex1**: hex0 + single-character labels
- **hex2**: hex1 + multi-character labels, relative pointers , word literals, alignment padding
- **M0**: Platform-specific macro assembler — adds `DEFINE name hex`, expands macros, resolves hex2-style labels/immediates, assembles in memory, and executes directly
- **as0**: A real assembler that supports a minimal subset of GNU assembler (GAS) syntax.

We keep several reference artifacts for comparison/debugging that are not part of the real bootstrap chain.

## Building and Testing

### Dependencies

A POSIX environment with:

- `qemu-system-riscv64`
- Binutils for RISC-V64
	- `riscv64-none-elf-gcc`
	- `riscv64-none-elf-as`
	- `riscv64-none-elf-objcopy`
	- `riscv64-none-elf-gdb`
	- etc.
- `just` (command runner)
- Standard POSIX utilities (`sed`, `tr`, `xxd`, `grep`, `bash`)

A Nix flake is provided (`nix develop`) but is not required.

### Running Tests

```sh
just test
```

This runs the full bootstrap chain on QEMU.

If you have access to Nix, you can also run `nix flake test`, which does the same thing.

## Debugging

For lower-level debugging (e.g. hex0), I managed to get figure out a multi-terminal workflow.

```sh
# Terminal 1: QEMU
just debug_hex0

# Terminal 2: GDB (uses .gdbinit)
gdb

# Terminal 3: Watch serial output
bat -p --paging=never qemu-dbg.out

# Terminal 4: Send input
echo 'test text' >> qemu-dbg.in
```

## Audit progress

Personal stage0-style audits (full human read-through of the hex source):

- `hex0.hex0`: Root seed; everything builds on it.
- `hex1.hex0`: Next step in the chain.
- `echo.M1`: Reference/demo, not a chain stage.

Later stages (`hex2`, `M0`, `as0`, …) were not audited to that standard.
A personal audit is not a shared trust root — others should re-audit if they
care — and audit is not formal verification; see
[Status](#status-read-this-first).

## Relevant Links

- <https://bootstrappable.org/>
- <https://reproducible-builds.org/>
- <https://github.com/oriansj/stage0>
- <https://github.com/fosslinux/live-bootstrap>
- <https://bootstrapping.miraheze.org/wiki/Main_Page>

## License

This repository is mixed-license.

Unless a file says otherwise, original work in this repository is licensed under
`GPL-3.0-or-later`. The full license text is available in
[`LICENSE`](LICENSE) and [`LICENSES/GPL-3.0-or-later.txt`](LICENSES/GPL-3.0-or-later.txt).
