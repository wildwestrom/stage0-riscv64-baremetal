# Bootstrapping without C

What is this? It's basically [`stage0`](https://github.com/oriansj/stage0) but for RISC-V on baremetal, and with no plans to get GCC up and running. I made heavy use of LLMs in doing this and I'm not proud. Yes, I understand that "root of trust" is the very problem `stage0` is trying to solve, but I really don't care enough to audit machine code seeds myself.

## Relevant Links

https://bootstrappable.org/
https://reproducible-builds.org/
https://github.com/oriansj/stage0
https://github.com/fosslinux/live-bootstrap

## The problem

I've been thinking about the bootstrapping problem.

Let's assume that C (like assembly) is fundamentally unsound; Just take it as a premise. I understand exactly the historical context of why C is so entrenched. No need to rehash why C "won".

We must start from somewhere in order to build up our systems, and indeed we can start pretty low, from machine code recorded as hexadecimal, constructed by cross-referencing a CPU architecture manual. The next stages then require that we go from inserting hexadecimal into hex0 into something that allows for a bit more control. The ability to calculate jump points so as to allow us to use aliases of where to jump. A few steps later and we have an assembler for the CPU. It's at this point we can then think about how to go from our particular CPU architecture to a compiler of a language for an abstract machine. In all cases, it is C. (One intermediate step is a scheme interpreter called `mes` written in C in order to make another C compiler.) There is no other bootstrappable toolchain where C is not an integral part.

If we could create a toolchain without C, then what could we use instead of C? I could say the same about C++. To get to the latest versions of GCC and Clang (or Rust for that matter) we must bootstrap C++ from C. As we all know (or just accept it again) C++ is a mess.

My urge is to simplify the chain, or start a new chain, but this requires ignoring the flawed but existing and functioning work already done. It would require carving out a system incompatible in profound ways to everything else out there. No compatibility with any software written today (because it all relies on C somewhere in the chain). No compatibility with firmware interfaces (because of the C ABI). No ability to run on existing operating systems (C ABI/POSIX).

I would still say this is a worthwhile project though, and let's proceed as such. I think specifically we should look at minimal languages for bootstrapping. Something with a specification that's 10 instead of 600 pages. Maybe even something formally verified like CakeML (which I know relies of HOL, which relies on SML, which relies on C or C++). I don't think it would be feasible to write a Standard ML-like language in assembly. It would need a prior high-level language to express the type system sufficiently.

Obviously we need some intermediate language(s).

First something a little nicer than assembly (post `M0`) which I'll call Tier 1:

- LISP: Garbage collector, way more familiar to me (Clojure was my first language before Rust), probably not easy to access registers or memory
- Forth: Supposedly trivial to implement in assembly, powerful, close to the hardware, but from what I saw, it's less readable than assembly. Not to mention the stack juggling I'll have to do in my head.
- Oberon: small spec, similar to C semantically, used to implement a whole OS, but possibly too early in the toolchain
- Something I don't know about.
- Something completely new: I'm nowhere near an expert that can design and implement a language in assembly.

I could easily just steal or port an existing Tier 1, but I'd still have to then use that for the next step.

Then something nicer than that but still simple and powerful. All of these currently rely on C as part of their bootstrap process. Tier 2.

- Oberon: for the reasons above, probably a good choice
- LISP: same problems as other lisps
- Standard ML: great type system, probably very hard to implement
- Something else I don't know about.
- Something completely new: I don't really want to design my own language at this stage.
- C???: No...

For all I know, I'll need many more steps in between, but hopefully nowhere close to the roughly 80 steps it takes to get to GCC in [`live-bootstrap`](https://github.com/fosslinux/live-bootstrap/blob/master/parts.rst).

Why wouldn't I accept an intermediate C (`cc_x86`, `M2 Planet`, `mescc`, `tinycc`)? Because, it begs the question of why undertake this project at all? Why not just compress some of the existing bootstrap process with more C? Again, this is because you would then leak C's ill-defined semantics everywhere up the chain. We're trying to build new foundations.

People have a vested interest in their software being safe and correct. We already pay the cost of not re-building the toolchain from scratch through all the effort in mitigation we do already.

## Where we're at

The bootstrap chain is functional through `hex1`:

- **hex0**: Minimal hex loader - reads hex bytes from UART, stores in memory, executes on Ctrl-D
- **hex1**: hex0 + single-character labels (`:x` to define, `@x` for B-format branches, `$x` for J-format jumps, `~x` for U-format upper immediate, `!x` for I-format lower immediate)

Working chain: `hex0.bin → hex0.hex0 → hex1.hex0 → echo.hex1`

The test suite verifies each stage can load and execute the next. Test programs echo characters via UART to confirm execution.

## Debugging

I managed to get debugging to work. You'll need a few terminals open.

Terminal 1 is going to have qemu running:

```sh
make debug_hex0
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
