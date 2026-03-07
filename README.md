# Foundations for Correct Computing

What if every layer of your software — from the first instruction up — was provably correct? This project builds a toolchain from scratch on RISC-V bare metal, starting from hand-auditable machine code, designed to make entire classes of bugs impossible by construction.

The master repository is on <https://github.com/wildwestrom/stage0-riscv64-baremetal>.

I made heavy use of LLMs in doing this and I'm not proud. Yes, I understand that "root of trust"/"trusting trust" is the very problem `stage0` is trying to solve, but I really don't care enough to audit machine code seeds myself right now.

## Why

**Software is unreliable.** Bugs cost money, time, and lives. We accept this as normal, but it's not inevitable.

**The foundation is the problem.** All software is built on layers. Every compiler was compiled by another compiler, built on libraries, linked against an OS — layers upon layers of assumptions. [Bootstrapping projects](https://bootstrappable.org/) start from hand-auditable machine code to make that chain fully transparent. But transparency alone isn't enough if the semantics at each layer are ill-defined.

Every existing bootstrapping path goes through C, a language with [undefined behavior](https://blog.llvm.org/2011/05/what-every-c-programmer-should-know_14.html) baked into its semantics. Those ill-defined semantics leak upward through every layer built on top. C++ inherits them. GCC and Clang are written in C++. Rust, Go, and nearly everything else bootstraps through one of those compilers. The entire ecosystem sits on a foundation that is, by specification, allowed to do anything.

**We can start over.** RISC-V gives us an open, well-specified instruction set. Bare metal gives us no inherited assumptions. By refusing to bootstrap through C, we can design for correctness from the ground up — choosing semantics that make bugs unrepresentable rather than merely unlikely.

## Correctness By Construction

"We know it works and we can prove it."

Why spend eternity hunting bugs when you can make them impossible to represent? This is the core design principle of the project. The techniques below represent the design space we're drawing from — not a checklist to implement all at once, but a toolkit of ideas that inform every decision about what this system's semantics should look like:

- Pure functional programming
- Linear types
- Dependent types
- Algebraic data types
- Errors as values
- Capability-based security
- Calculating compilers
- Formal verification
- Proofs as programs (Curry-Howard correspondence)
- Non-turing complete languages / Total programming languages
- Borrow checking
- Recursion schemes (ana-,cata-,hylo-morphisms)
- Communicating sequential processes
- The actor model

Some of these ideas feel natural and pleasant to use. Some are so academic they're hard to wrap your head around, let alone implement. But it doesn't have to stay that way. The *monad* was an ivory tower category theory concept until languages like Rust and Swift called them `Result` and `Option`.

## The Approach

This project follows the [`stage0`](https://github.com/oriansj/stage0) bootstrap philosophy — start from hex, build up through progressively more capable assemblers — but diverges after the macro assembler stage. Where `stage0` builds toward C, we don't.

**Current bridge: Forth.** After the macro assembler, the chain currently goes through [DerzForth](https://github.com/theandrew168/derzforth/). Forth is a practical choice — it's simple enough to implement in macro assembly and powerful enough to build the next stage — but it's not an ideological commitment.

**Goal: a formally verified compiler** with correctness-oriented semantics. Formal verification appears to be the strongest answer to the question "how do we know this works?" There are many open research directions between here and there:

- What are the right semantic primitives for a correctness-first language?
- What intermediate stages are needed between Forth and a verified compiler?
- What are the best abstractions for bootstrapping, and in what order should they be implemented?

These are deliberate research questions, not signs of aimlessness. The path from macro assembly to a verified compiler is uncharted — that's what makes it worth exploring.

**Why not intermediate C?** Because it would defeat the purpose. Accepting C (`cc_x86`, `M2 Planet`, `mescc`, `tinycc`) at any point in the chain means accepting its ill-defined semantics as part of your foundation. Why undertake this project at all if you're going to leak C's problems upward? The whole point is to answer: *what semantics do we actually want as the foundation?*

## Where We're At

The bootstrap chain has been tested on QEMU with [CHERI (Capability Hardware Enhanced RISC Instructions)](https://www.cl.cam.ac.uk/research/security/ctsrd/cheri/) support — an instruction set extension that adds capability-based security at the hardware level.

The chain stages:

- **hex0**: Minimal hex loader - reads hex bytes from UART, stores in memory, executes on Ctrl-D
- **hex1**: hex0 + single-character labels (`:x` to define, `@x` for B-format branches, `$x` for J-format jumps, `~x` for U-format upper immediate, `!x` for I-format lower immediate)
- **hex2**: hex1 + multi-character labels (`:label_name`), relative pointers (`%label`, `&label`), word literals (`.XXXXXXXX`), alignment padding (`<`)
- **M0**: Platform specific macro assembler - adds `DEFINE name hex`, expands macros, resolves hex2-style labels/immediates, assembles in memory, and executes directly

Current working chain:
- Generate the initial `hex0.bin` seed from the handwritten `hex0.hex0`.
- Load `hex0.bin` into QEMU.
- Feed `hex0.hex0` over UART.
- Send execute signal (`0x04`/Ctrl-D).
- Feed `hex1.hex0`
- Send execute signal (`0x04`/Ctrl-D).
- Feed `hex2.hex1`
- Send execute signal (`0x04`/Ctrl-D).
- Feed `M0.hex2`
- Send execute signal (`0x04`/Ctrl-D).
- Feed `derzforth.M1`.
- Send execute signal (`0x04`/Ctrl-D).
- Send `foo`, confirm ` ?`.
- Send `key emit`, then `A`, confirm `A ok`.
- Send `bye` to power off QEMU immediately when the test is done.

`just test` verifies this full bootstrap chain. Right now that is still a smoke test, not a proof that the Forth is mature or fully exercised.

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

This runs the full bootstrap chain on QEMU. See all available recipes with `just --list`.

If you have access to Nix, you can also run `nix flake test`, which does the same thing.

## Other Goals & Considerations

### Concurrency/Parallelism

In C and pretty much every other language, we primarily write code meant to execute from top to bottom, sequentially. Asynchronous, concurrent, and parallel programming is often slapped on as an afterthought (perhaps with BEAM languages as a notable exception).

This deserves serious thought early on so it doesn't become a bolted-on problem later.

### ABI and Calling Convention

Since this project doesn't care about backwards compatibility, it's an opportunity to design an ABI from scratch. Whether RISC-V's psABI is already close to optimal or whether a clean-slate design would be better is an open question.

### Visual/Structured Programming

There are many projects that attempted to make visual programming viable, but they'll never reach widespread adoption until they become self-hosting. Text is also fragile — editing code should be structured and incorrect syntax should be impossible to type. So many arguments about syntax could be killed in one fell swoop if the language could look however you prefer, but maintain what's important: Semantics.

**Inspiration:**
- [Orenolisp](https://github.com/illiichi/orenolisp)
- [fructure](https://fructure-editor.tumblr.com/)
- [Lamdu](https://www.lamdu.org/)
- [Kronark](https://www.youtube.com/@Kronark)
- [Scratch](https://scratch.mit.edu/)
- [Blockly](https://developers.google.com/blockly)
- ["Zoom Out": The missing feature of IDEs](https://medium.com/source-and-buggy/zoom-out-the-missing-feature-of-ides-f32d0f36f392)

### Binary-First Display

Inspired by ["the best way to count"](https://youtu.be/rDDaEVcwIJM) — a case that base-10 is not great, seximal (base-6) is no better, and that binary is ideal for learning, counting, and doing calculations. The video also proposes a unique way of displaying base-2. Below is an example of 0-7 in this binary representation. More info here: <https://github.com/lucillablessing/thebestwaytocount>

![new binary representation in](./binary-demo.svg)

```xml
<svg width="151" height="16" viewBox="0 0 151 16" xmlns="http://www.w3.org/2000/svg" shape-rendering="crispEdges">
  <path d="
    M0 10h1v6H0z M1 15h4v1H1z M5 10h1v6H5z M6 15h4v1H6z M10 10h1v6h-1z
    M20 10h1v6h-1z M21 15h4v1h-4z M25 10h1v6h-1z M26 15h4v1h-4z M30 0h1v16h-1z
    M40 10h1v6h-1z M41 15h4v1h-4z M45 0h1v16h-1z M46 15h4v1h-4z M50 10h1v6h-1z
    M60 10h1v6h-1z M61 15h4v1h-4z M65 0h1v16h-1z M66 15h4v1h-4z M70 0h1v16h-1z
    M80 0h1v16h-1z M81 15h4v1h-4z M85 10h1v6h-1z M86 15h4v1h-4z M90 10h1v6h-1z
    M100 0h1v16h-1z M101 15h4v1h-4z M105 10h1v6h-1z M106 15h4v1h-4z M110 0h1v16h-1z
    M120 0h1v16h-1z M121 15h4v1h-4z M125 0h1v16h-1z M126 15h4v1h-4z M130 10h1v6h-1z
    M140 0h1v16h-1z M141 15h4v1h-4z M145 0h1v16h-1z M146 15h4v1h-4z M150 0h1v16h-1z
  " fill="currentColor" />
</svg>
```

This means displays, terminals (not VT-descended — maybe [Arcan-based](https://arcan-fe.com/2025/01/27/sunsetting-cursed-terminal-emulation/)), hex editors, etc. should use this binary display, with grouping adjustable to what's comfortable for the user.

## Debugging

I managed to get debugging to work. You'll need a few terminals open.

Terminal 1 is going to have qemu running:

```sh
just debug_hex0
```

After that open Terminal 2 and run gdb:
The `.gdbinit` file should set everything up.

```sh
gdb
```

Then in Terminal 3, set up something to watch our pipe `qemu-dbg.out`.
I use bat.

```sh
bat -p --paging=never qemu-dbg.out
```

In terminal 4 we'll send our text.

```sh
echo 'test text' >> qemu-dbg.in
```

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

[`derzforth/`](derzforth) is upstream
DerzForth by Andrew Dailey and remains MIT licensed. The full MIT text is
available in
[`derzforth/LICENSE`](derzforth/LICENSE) and [`LICENSES/MIT.txt`](LICENSES/MIT.txt).

Files derived from DerzForth outside [`derzforth/`](derzforth)
preserve the upstream MIT notice in their headers. If there is any conflict
between this summary and a file header, follow the file header.
