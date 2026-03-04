# Bootstrapping without C

Let's assume that C (like assembly) is fundamentally unsound. Why then are all our most critical systems and infrastructure built upon it then?

That is where this project comes in. It's basically [`stage0`](https://github.com/oriansj/stage0) but for RISC-V on baremetal, and with no plans to get GCC up and running. This will be the toolchain that builds the foundation for all software of the future.

I made heavy use of LLMs in doing this and I'm not proud. Yes, I understand that "root of trust"/"trusting trust" is the very problem `stage0` is trying to solve, but I really don't care enough to audit machine code seeds myself right now.

## Relevant Links

- https://bootstrappable.org/
- https://reproducible-builds.org/
- https://github.com/oriansj/stage0
- https://github.com/fosslinux/live-bootstrap
- https://bootstrapping.miraheze.org/wiki/Main_Page

## The Problem

We must start from somewhere in order to build up our systems, and indeed we can start pretty low; From machine code recorded as hexadecimal, constructed by cross-referencing a CPU architecture manual. The next stages then require that we go from inserting hexadecimal into hex0 into something that allows for a bit more control. The ability to calculate jump points allowing us to use aliases pointing where in the program to jump. Control flow.

A few steps later and we have an assembler for the CPU. It's at this point we can then think about how to go from our particular CPU architecture to a compiler of a language for an abstract machine. In all existing bootstrapping projects, this higher level language is none other than C. If we could create a toolchain without C, then what could we use instead of C? I could say the same about C++. To get to the latest versions of GCC and Clang (or Rust for that matter) we must bootstrap C++ from C. As we all know (or just accept it as a premise), C++ is a mess.

My urge is to simplify the chain, by starting an entirely new chain. This requires ignoring the flawed but existing and functioning work already done. It would require carving out a system incompatible in profound ways to everything else out there. No compatibility with any software written today (it all relies on a C toolchain). No compatibility with firmware interfaces (because of the C ABI). No ability to run on existing operating systems (C ABI/POSIX).

I believe we're paying far more for buggy, unreliable, and expensive software than if we comitted fully to **correctness by construction**. If that's not a worthwhile undertaking, I don't know what is. 

## Possible Roadmap

I've done some research on minimal languages for bootstrapping. Something with a specification that's 10 instead of 600 pages is probably a good idea. Maybe even something formally verified like CakeML (which I know relies of HOL, which relies on SML, which relies on C or C++). I don't think it would be feasible to write a Standard ML-like language in assembly. It would need a prior high-level language to express the type system sufficiently.

Obviously we need some intermediate language(s).

First something a little nicer than assembly (post `M0`) which I'll call Tier 1:

- LISP: Garbage collector, way more familiar to me (Clojure was my first language before Rust), probably not easy to access registers or memory
- Forth: Supposedly trivial to implement in assembly, powerful, close to the hardware, but from what I saw, it's less readable than assembly. Not to mention the stack juggling I'll have to do in my head.
- [Oberon](https://projectoberon.net/): small spec, similar to C semantically, used to implement a whole OS, but possibly too early in the toolchain
- Something I don't know about.
- Something completely new: I'm nowhere near an expert that can design and implement a language in assembly.

I could easily just steal or port an existing Tier 1, but I'd still have to then use that for the next step.

Then something nicer than that but still simple and powerful. All of these currently rely on C as part of their bootstrap process. Tier 2.

- [Oberon](https://projectoberon.net/): for the reasons above, probably a good choice
- LISP: same problems as other lisps
- Standard ML: great type system, probably very hard to implement
- Something else I don't know about.
- Something completely new: I don't really want to design my own language at this stage.
- C???: No...

For all I know, I'll need many more steps in between, but hopefully nowhere close to the roughly 80 steps it takes to get to GCC in [`live-bootstrap`](https://github.com/fosslinux/live-bootstrap/blob/master/parts.rst).

Why wouldn't I accept an intermediate C (`cc_x86`, `M2 Planet`, `mescc`, `tinycc`)? Because, it begs the question: Why undertake this project at all? Why not just compress some of the existing bootstrap process with more C? Again, this is because you would then leak C's ill-defined semantics everywhere up the chain. We're trying to build new foundations.

## Where we're at

The bootstrap chain has been tested on QEMU with CHERI support:

- **hex0**: Minimal hex loader - reads hex bytes from UART, stores in memory, executes on Ctrl-D
- **hex1**: hex0 + single-character labels (`:x` to define, `@x` for B-format branches, `$x` for J-format jumps, `~x` for U-format upper immediate, `!x` for I-format lower immediate)
- **hex2**: hex1 + multi-character labels (`:label_name`), relative pointers (`%label`, `&label`), word literals (`.XXXXXXXX`), alignment padding (`<`)
- **M0**: Platform specific macro assembler - adds `DEFINE name hex`, expands macros, resolves hex2-style labels/immediates, assembles in memory, and executes directly

Working chain:
- Generate the initial `hex0.bin` seed from the handwritten `hex0.hex0`.
- Load `hex0.bin` into QEMU.
- Feed `hex0.hex0` over UART.
- Send execute signal (`0x04`).
- Feed `hex1.hex0`
- Send execute signal (`0x04`).
- Feed `hex2.hex1`
- Send execute signal (`0x04`).
- Feed `M0.hex2`
- Send execute signal (`0x04`).
- Feed `echo.M1`.
- Send execute signal (`0x04`).
- Send `test` text.
- Confirtm `test` text gets echoed back out.

`just test` verifies this full bootstrap chain.

The assembly version of `hex0` is kept only as a reference artifact for comparison/debugging. It is not part of the real bootstrap chain.

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

## Aspirational Considerations

I do not intend to simply just build an alternative toolchain, I want a secure and provably correct foundation for future computing.

To do this, I have considered some other areas for improvement, but a lot of these are impossible to do in assembly, so they'll have to be way higher up the toolchain.

I currently have no idea what the ideal abstractions are at each stage.

#### Correctness By Construction

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

#### CHERI

[CHERI (Capability Hardware Enhanced RISC Instructions)](https://www.cl.cam.ac.uk/research/security/ctsrd/cheri/) is an instruction set extension designed to add capability-based security at the hardware level. Basically, you can run ill-defined C code, and it will crash when accessing memory that it shouldn't. Note that while this does solve spatial access problems, it does not solve temporal access problems (use-after-free, etc.).

This repository is already making use of a version of QEMU with CHERI support.

#### Concurrency/Parallelism

In C and pretty much every other language, we primarily write code meant to execute from top to bottom, sequentially. Asynchronous, concurrent, and parallel programming is often slapped on as an afterthought (perhaps with BEAM languages as a notable exception).

I really want to think hard about this so it doesn't bite me later on.

#### ABI and Calling Convention

Since I don't care about backwards compatibility, I could in theory design an ABI better than RISC-V's psABI. I do not yet know enough to say whether or not psABI is already close to optimal and trying to re-design it is a fools errand.

#### Text Sucks Ass

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
