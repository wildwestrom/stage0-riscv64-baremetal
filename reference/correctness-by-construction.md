# Correctness By Construction

Why spend eternity hunting bugs when you can make them impossible to represent?

We should instead be saying "We know this works and we can prove it".

## Techniques

There are many tools and techniques out there meant to prevent bugs from happening in the first place.

Some of these ideas feel natural and pleasant to use. Some are so academic they're hard to wrap your head around, let alone implement. But it doesn't have to stay that way. The *monad* was an ivory tower category theory concept until languages like Rust and Swift called them `Result` and `Option`.

## Type Systems
- Algebraic data types
- Linear types
- Dependent types
- Refinement types
- Session types

## Ownership & Memory Safety
- Borrow checking
- Region-based memory management
- Pointer capabilities (CHERI)

## Programming Model
- Pure functional programming
- Errors as values
- Total programming / Non-turing complete languages
- Recursion schemes (ana-, cata-, hylo-morphisms)
- Effect systems / Algebraic effects
- Immutability by default

## Concurrency
- Communicating sequential processes
- The actor model

## Verification & Proof
- Formal verification
- Proofs as programs (Curry-Howard correspondence)
- Calculating compilers
- Property-based testing

## Security
- Capability-based security


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

