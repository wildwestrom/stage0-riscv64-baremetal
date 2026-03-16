# Stage-0 but without C

From machine code to a correct-by-construction compiler! That's the goal anyway.

The master repository is on <https://github.com/wildwestrom/stage0-riscv64-baremetal>.

# Wait, what?

To those who already know what bootstrapping is, skip to the next section.

>	Do you know how to make yoghurt? The first step is to add yoghurt to milk! How can you build a compiler like GCC? The first step is to get a compiler that can compile the compiler.
> — [bootstrappable.org](https://bootstrappable.org/)

So where do you get your C compiler from? Do you download it from Microsoft's website? Do you get it from your Linux package repository? Does one come pre-installed on your computer?

There are many ways to get a compiler. Once you have a compiler you can build another compiler! This is the way most compilers are developed, both old and new. However you see there's a chicken and egg problem, right? Where did the first compiler come from? Bootstrapping is the process of creating the toolchain that builds the first compiler and every compiler after that.

## Why

Software sucks. It's buggy, unreliable, and slow. Why do we put up with this? More importantly, what's the cause? 

In fact, there are many causes. I'm tackling just one, and that is the abstractions we all build on top of. C works great as a portable assembler, but can you guarantee anything about its behavior? Are you sure there are no stack smashing or off-by-one edge-cases? Would you run your C on the Therac-25? An F-35 fighter jet? Maybe you program like NASA and follow strict discipline for correctness. Best case scenario, you run your C code through CompCert C and get a guarantee that your code follows C's ill-defined semantics exactly. 

Enough! Let's start from 0. Stage 0 to be exact. This project was heavily inspired by [oriansj/stage0](github.com/oriansj/stage0) and [live-bootstrap](https://github.com/fosslinux/live-bootstrap/blob/master/parts.rst). I knew this was the direction I wanted to go, but why the hell are there 80+ steps to get an old version of GCC?

## The Approach

This project follows the [`stage0`](https://github.com/oriansj/stage0) bootstrap philosophy: Start from hex, build up through progressively more capable assemblers, but diverges after the macro assembler stage. Where `stage0` builds toward C, we don't.

**Goal: a formally verified compiler** with correctness-oriented semantics. Formal verification appears to be the strongest answer to the question "how do we know this works?" These I think are the important questions that still need answers:

- What are the right semantics for a correctness-first language?
- How do we build up to such a language?

**Why not intermediate C?** Because it would defeat the purpose. Accepting C (`cc_x86`, `M2 Planet`, `mescc`, `tinycc`) at any point in the chain means accepting its ill-defined semantics as part of the foundation. Why undertake this project at all if you're going to leak C's problems upward? The whole point is to answer: *What semantics do we actually want as the foundation?*

## Where We're At

The bootstrap chain has been tested on QEMU with [CHERI (Capability Hardware Enhanced RISC Instructions)](https://www.cl.cam.ac.uk/research/security/ctsrd/cheri/) support. An instruction set extension that adds capability-based security at the hardware level. I don't fully understand it. Just know it's important for later.

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

We keep several reference artifacts for comparison/debugging that are not part of the real bootstrap chain.

## Building and Testing

### Dependencies

A POSIX environment with:

- `qemu-system-riscv64` with CHERI support (the binary is called `qemu-system-riscv64-purecap`)
- `riscv64-none-elf-gcc` (and binutils: `as`, `objcopy`)
- `riscv64-none-elf-gdb` (for debugging)
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

## Caveat

I made heavy use of LLMs in doing this and I'm not proud. Yes, I understand that "root of trust"/"trusting trust" is the very problem `stage0` is trying to solve, but I really don't care enough to audit machine code seeds myself right now.

### Audit progress

- `hex0.hex0`: It is arguably the most important one as we build everything on top of it.

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
