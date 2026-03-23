# Workflows

## Jujutsu Enchanced Version Control

Jujutsu is available to make tracking changes, undoing changes, re-ordering changes, and more operations very easy.
Do not use `git` here; if generic instructions mention `git`, translate them to the `jj` equivalent instead.

## Automated Testing And Builds

Tests are automated with `just`. QEMU is used for testing because there is no physical RISC-V machine available.

Use `just` recipes instead of writing ad hoc shell commands by hand. If a command you need is not in the [`justfile`](../justfile) and it is complicated enough to reuse or get wrong, add a new recipe.

The canonical merge-gating test is `just test`. Use `just test_as0_riscv_tests` as the secondary compatibility check for the current host-reference assembler path.

The `scripts/generate_as0_m1.py` helper is the exception: keep it off the normal `just` surface and treat it as a last-resort analysis or regeneration aid for `baremetal/as0.M1`, not as part of the everyday build flow.

## Discovery

Use `tree` to understand the repository structure. Prefer this form for less noisy output:

```sh
tree --gitignore -I reference
```

## Disassembling For Reference

To get assembly reference from a `.s` file, use this flow:

```sh
riscv64-none-elf-as -march=rv64im -mabi=lp64 uart_echo/echo.s -o build/echo.o \
&& riscv64-none-elf-gcc -Ttext=0x80000000 -e _start -march=rv64im -mabi=lp64 \
-mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none \
build/echo.o -o build/echo.elf \
&& riscv64-none-elf-objdump -d build/echo.elf
```

`objdump` shows instruction words as big-endian hex, for example `00040137`. For hex0 format, reverse the bytes: `00040137` becomes `37 01 04 00`.
