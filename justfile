set shell := ["bash", "-euo", "pipefail", "-c"]

as := "riscv64-none-elf-as"
cc := "riscv64-none-elf-gcc"
objcopy := "riscv64-none-elf-objcopy"
build_dir := "build"
hex0_c := "baremetal/high_level_prototype/stage0_monitor.c"
hex0_ld := "baremetal/high_level_prototype/stage0_monitor.ld"
m0_hex2 := "baremetal/M0.hex2"
derzforth_src := "baremetal/GAS/derzforth.s"
derzforth_elf := "build/derzforth.elf"
derzforth_debug_elf := "build/derzforth.debug.elf"
qemu := "qemu-system-riscv64-purecap -nographic -monitor none -machine virt -bios none -m 24M"
asflags := "-march=rv64i -mabi=lp64"
asflags_m0 := "-march=rv64i -mabi=lp64 --defsym M0_HEAP_BASE=0x80100000 --defsym M0_INPUT_BASE=0x80200000 --defsym M0_STACK_TOP=0x80500000"
cflags := "-Oz -march=rv64i -mabi=lp64 -mcmodel=medany -msmall-data-limit=0 -ffreestanding -fno-builtin -fno-stack-protector -fomit-frame-pointer -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-ident -ffunction-sections -fdata-sections"
c_asmflags := "-Oz -march=rv64i -mabi=lp64 -mcmodel=medany -msmall-data-limit=0 -ffreestanding -fno-builtin -fno-stack-protector -fomit-frame-pointer -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-ident -ffunction-sections -fdata-sections -fverbose-asm"
ldflags := "-Ttext=0x80000000 -e _start -march=rv64i -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none -Wl,--strip-all"
ldflags_debug := "-Ttext=0x80000000 -e _start -march=rv64i -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none"

hex0_bin:
  mkdir -p {{build_dir}}
  ./scripts/hex0_to_bin.sh baremetal/hex0.hex0 {{build_dir}}/hex0.bin

# Optional audit helper: regenerate the deeply annotated view
# when a particular instruction sequence needs closer inspection.
annotate_hex0:
  python3 scripts/annotate_hex0.py baremetal/hex0.hex0 {{build_dir}}/hex0_annotated.hex0

test: test_full_chain_lisp

test_full_chain_lisp: hex0_bin
  bash -euxo pipefail -c '\
    mkdir -p {{build_dir}}; \
    rm -f {{build_dir}}/full_chain_lisp.out {{build_dir}}/full_chain_lisp.actual; \
    status=0; \
    ( \
      cat baremetal/hex0.hex0; \
      printf "\x04"; \
      cat baremetal/hex1.hex0; \
      printf "\x04"; \
      cat baremetal/hex2.hex1; \
      printf "\x04"; \
      cat {{m0_hex2}}; \
      printf "\x04"; \
      cat baremetal/riscv64_defs.M1 baremetal/derzforth.M1; \
      printf "\x04"; \
      printf "\n"; \
      cat derzforth/lexicons/prelude.forth; \
      printf "\n"; \
      cat lexicons/control.forth; \
      printf "\n"; \
      cat lexicons/lisp.forth; \
      printf "\nlisp-init\n0x40 emit 10 emit lisp-repl\n"; \
      cat tests/lisp_test.lisp; \
    ) | timeout "${TIMEOUT_FULL_CHAIN_LISP:-30.0s}" {{qemu}} -serial stdio -kernel {{build_dir}}/hex0.bin > {{build_dir}}/full_chain_lisp.out 2>/dev/null || status=$?; \
    sed -n "/^@\$/,\${/^@\$/d;p}" {{build_dir}}/full_chain_lisp.out > {{build_dir}}/full_chain_lisp.actual; \
    if [[ "$status" -eq 0 || "$status" -eq 124 ]] && cmp -s {{build_dir}}/full_chain_lisp.actual tests/lisp.expected; then \
      printf "PASS test_full_chain_lisp\n"; \
    else \
      printf "FAIL test_full_chain_lisp: see %s and %s\n" "{{build_dir}}/full_chain_lisp.out" "{{build_dir}}/full_chain_lisp.actual" >&2; \
      exit 1; \
    fi \
  '

debug_hex0:
  bash -euxo pipefail -c '\
    mkdir -p {{build_dir}}; \
    {{as}} {{asflags}} baremetal/GAS/hex0.s -o {{build_dir}}/hex0.o; \
    {{cc}} {{ldflags_debug}} {{build_dir}}/hex0.o -o {{build_dir}}/hex0.debug.elf; \
    rm -f qemu-dbg.in qemu-dbg.out; \
    mkfifo qemu-dbg.in qemu-dbg.out; \
    exec {{qemu}} -serial pipe:qemu-dbg -kernel {{build_dir}}/hex0.debug.elf -gdb tcp::1234 \
  '

derzforth_elf:
  mkdir -p {{build_dir}}
  {{cc}} {{ldflags}} {{derzforth_src}} -o {{derzforth_elf}}

derzforth_debug_elf:
  mkdir -p {{build_dir}}
  {{cc}} {{ldflags_debug}} {{derzforth_src}} -o {{derzforth_debug_elf}}

run_derzforth: derzforth_elf
  exec {{qemu}} -serial stdio -kernel {{derzforth_elf}}

test_derzforth: derzforth_elf
  bash -euxo pipefail -c '\
    mkdir -p {{build_dir}}; \
    rm -f {{build_dir}}/derzforth.out {{build_dir}}/derzforth.actual; \
    status=0; \
    printf "\nfoo\nkey emit\nA\nbye\n" | timeout "${TIMEOUT_DERZFORTH:-5.0s}" {{qemu}} -serial stdio -kernel {{derzforth_elf}} > {{build_dir}}/derzforth.out 2>/dev/null || status=$?; \
    sed -n "/^foo$/,\$p" {{build_dir}}/derzforth.out > {{build_dir}}/derzforth.actual; \
    if [[ "$status" -eq 0 ]] && cmp -s {{build_dir}}/derzforth.actual tests/derzforth.expected; then \
      printf "PASS test_derzforth\n"; \
    else \
      printf "FAIL test_derzforth: see %s and %s\n" "{{build_dir}}/derzforth.out" "{{build_dir}}/derzforth.actual" >&2; \
      exit 1; \
    fi \
  '

test_control: derzforth_elf
  bash -euxo pipefail -c '\
    mkdir -p {{build_dir}}; \
    rm -f {{build_dir}}/control.stdin {{build_dir}}/control.out {{build_dir}}/control.actual; \
    printf "\n" > {{build_dir}}/control.stdin; \
    cat derzforth/lexicons/prelude.forth >> {{build_dir}}/control.stdin; \
    printf "\n" >> {{build_dir}}/control.stdin; \
    cat lexicons/control.forth >> {{build_dir}}/control.stdin; \
    printf "\n" >> {{build_dir}}/control.stdin; \
    cat lexicons/tests/control_test.forth >> {{build_dir}}/control.stdin; \
    status=0; \
    timeout "${TIMEOUT_CONTROL:-8.0s}" {{qemu}} -serial stdio -kernel {{derzforth_elf}} < {{build_dir}}/control.stdin > {{build_dir}}/control.out 2>/dev/null || status=$?; \
    sed -n "/^test-if$/,\$p" {{build_dir}}/control.out > {{build_dir}}/control.actual; \
    if [[ "$status" -eq 0 ]] && cmp -s {{build_dir}}/control.actual tests/control.expected; then \
      printf "PASS test_control\n"; \
    else \
      printf "FAIL test_control: see %s and %s\n" "{{build_dir}}/control.out" "{{build_dir}}/control.actual" >&2; \
      exit 1; \
    fi \
  '

debug_lisp_start break="":
  python3 scripts/debug_session.py start --mode lisp {{if break != "" { "--break-location " + quote(break) } else { "" }}}

debug_cmd *args:
  python3 scripts/debug_session.py {{args}}

clean:
  rm -rf {{build_dir}}
