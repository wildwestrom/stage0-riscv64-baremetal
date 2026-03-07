# Bootstrapping without C

The master repository is on <https://github.com/wildwestrom/stage0-riscv64-baremetal>.

Let's assume that C (like assembly) is fundamentally unsound. Why then are all our most critical systems and infrastructure built upon it then?

That is where this project comes in. It's basically [`stage0`](https://github.com/oriansj/stage0) but for RISC-V on baremetal, and with no plans to get GCC up and running. This will be the toolchain that builds the foundation for all software of the future.

I made heavy use of LLMs in doing this and I'm not proud. Yes, I understand that "root of trust"/"trusting trust" is the very problem `stage0` is trying to solve, but I really don't care enough to audit machine code seeds myself right now.

## Relevant Links

- <https://bootstrappable.org/>
- <https://reproducible-builds.org/>
- <https://github.com/oriansj/stage0>
- <https://github.com/fosslinux/live-bootstrap>
- <https://bootstrapping.miraheze.org/wiki/Main_Page>

## The Problem

We must start from somewhere in order to build up our systems, and indeed we can start pretty low; From machine code recorded as hexadecimal, constructed by cross-referencing a CPU architecture manual. The next stages then require that we go from inserting hexadecimal into hex0 into something that allows for a bit more control. The ability to calculate jump points allowing us to use aliases pointing where in the program to jump. Control flow.

A few steps later and we have an assembler for the CPU. It's at this point we can then think about how to go from our particular CPU architecture to a compiler of a language for an abstract machine. In all existing bootstrapping projects, this higher level language is none other than C. If we could create a toolchain without C, then what could we use instead of C? I could say the same about C++. To get to the latest versions of GCC and Clang (or Rust for that matter) we must bootstrap C++ from C. As we all know (or just accept it as a premise), C++ is a mess.

My urge is to simplify the chain, by starting an entirely new chain. This requires ignoring the flawed but existing and functioning work already done. It would require carving out a system incompatible in profound ways to everything else out there. No compatibility with any software written today (it all relies on a C toolchain). No compatibility with firmware interfaces (because of the C ABI). No ability to run on existing operating systems (C ABI/POSIX).

I believe we're paying far more for buggy, unreliable, and expensive software than if we comitted fully to **correctness by construction**. If that's not a worthwhile undertaking, I don't know what is. 

## Roadmap

The question used to be "what comes after `M0`?" Right now the answer is Forth. I copied in [DerzForth](https://github.com/theandrew168/derzforth/), and got it into the bootstrap chain.

At the moment I have smoke tests, not deep confidence. I do not yet understand Forth well enough to treat it as a comfortable long-term programming environment, but it looks like a plausible bridge between macro assembly and something nicer.

I also originally thought the next question would be what language to use. Turs out the right question is "what semantics are absolutely essential for correct and trusted computing?" I really don't know at this point. There's just a whole grab-bag of concepts in my head (see [Correctness By Construction](#correctness-by-construction)) that I can draw from and experiment with, but that's not good enough for me.

I still think formal verification is the best answer to this question at the moment, there are so many unanswered questions. Perhaps the very most important question is: "What are the best abstractions to use for bootstrapping the final goal and in what order should they be implemented?"

For all I know, I'll need many more intermediate steps to get to a formally verified compiler, but hopefully nowhere close to the roughly 80 steps it takes to get to GCC in [`live-bootstrap`](https://github.com/fosslinux/live-bootstrap/blob/master/parts.rst).

Why wouldn't I accept an intermediate C (`cc_x86`, `M2 Planet`, `mescc`, `tinycc`)? Because, it begs the question: Why undertake this project at all? Why not just compress some of the existing bootstrap process with more C? Again, this is because you would then leak C's ill-defined semantics everywhere up the chain. The question remaining is "what semantics do we want as the foundation?"

## Where we're at

The bootstrap chain has been tested on QEMU with CHERI support:

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

`just test` verifies this full bootstrap chain. Right now that is still a smoke test, not a proof that the Forth is mature or that I know how to use it well yet.

We keep several reference artifacts for comparison/debugging that are not part of the real bootstrap chain.

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

## Essential Goals

### Correctness By Construction

"We know it works and we can prove it."

Isn't that a wonderful thought? Why spend eternity hunting bugs when you can make them impossible to represent? To this end, various techniques have been proposed, researched, and implemented by people much smarter than me.

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

Some ideas feel natural and pleasant to use. Some are so academic I can't wrap my head around them, let alone implement myself. It doesn't have to stay that way though. The *monad* was an ivory tower category theory concept until languages like Rust and Swift called them `Result` and `Option`.

### CHERI

[CHERI (Capability Hardware Enhanced RISC Instructions)](https://www.cl.cam.ac.uk/research/security/ctsrd/cheri/) is an instruction set extension designed to add capability-based security at the hardware level. Basically, you can run ill-defined C code, and it will crash when accessing memory that it shouldn't.

This repository is already making use of a version of QEMU with CHERI support.

### Concurrency/Parallelism

In C and pretty much every other language, we primarily write code meant to execute from top to bottom, sequentially. Asynchronous, concurrent, and parallel programming is often slapped on as an afterthought (perhaps with BEAM languages as a notable exception).

I really want to think hard about this so it doesn't bite me later on.

### ABI and Calling Convention

Since I don't care about backwards compatibility, I could in theory design an ABI better than RISC-V's psABI. I do not yet know enough to say whether or not psABI is already close to optimal and trying to re-design it is a fools errand.

## Aspirational Considerations

Not only do I want a secure and provably correct foundation for future computing, I also want computers to be nice to use.

To do this, I have considered some other areas for improvement, but they're out of scope for right now.

### Text Sucks

There are many projects that attempted to make visual programming viable, but I'd argue that they'll never reach widespread adoption until they become self-hosting. I would consider this the BARE MINIMUM to be considered a "real" programming language (not that non-self-hosting languages aren't real languages, but I'm appealing to the C peoples' sensibilities).

Text is also fragile. Editing code should be structured and incorrect syntax should be impossible to type. So many arguments about syntax could be killed in one fell swoop if the language could look however you prefer, but maintain what's important: Semantics.

**Inspiration:**
- [Orenolisp](https://github.com/illiichi/orenolisp)
- [fructure](https://fructure-editor.tumblr.com/)
- [Lamdu](https://www.lamdu.org/)
- [Kronark](https://www.youtube.com/@Kronark)
- [Scratch](https://scratch.mit.edu/)
- [Blockly](https://developers.google.com/blockly)
- ["Zoom Out": The missing feature of IDEs](https://medium.com/source-and-buggy/zoom-out-the-missing-feature-of-ides-f32d0f36f392)

### Binary First

This is extreme levels of re-thinking, but nonetheless falls within the aspirational section of this document.

Inspired by ["the best way to count"](https://youtu.be/rDDaEVcwIJM), I say we display all numbers in binary form. If you haven't seen the video, basically it argues that base-10 is not great, seximal (base-6) is not much better, and that binary is ideal for learning, counting, and doing calculations. In the video they also created a unique way of showing base-2. Below is an example of 0-7 in this binary representation.

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

This means I want text displays, terminals (but not VT descended, maybe [Arcan-based](https://arcan-fe.com/2025/01/27/sunsetting-cursed-terminal-emulation/)), hex editors, etc. to use this new binary display. Of course we should allow the grouping to be changed depending on what's comfortable for the user to read.

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
