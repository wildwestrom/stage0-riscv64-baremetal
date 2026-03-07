set shell := ["bash", "-euo", "pipefail", "-c"]

as := "riscv64-none-elf-as"
cc := "riscv64-none-elf-gcc"
objcopy := "riscv64-none-elf-objcopy"
build_dir := "build"
hex0_c := "baremetal/high_level_prototype/stage0_monitor.c"
hex0_ld := "baremetal/high_level_prototype/stage0_monitor.ld"
m0_hex2 := "baremetal/M0.hex2"
derzforth_src := "baremetal/GAS/derzforth.s"
derzforth_m1_src := "baremetal/derzforth.M1"
derzforth_elf := "build/derzforth.elf"
asflags := "-march=rv64i -mabi=lp64"
asflags_m0 := "-march=rv64i -mabi=lp64 --defsym M0_HEAP_BASE=0x80100000 --defsym M0_INPUT_BASE=0x80200000 --defsym M0_STACK_TOP=0x80500000"
cflags := "-Oz -march=rv64i -mabi=lp64 -mcmodel=medany -msmall-data-limit=0 -ffreestanding -fno-builtin -fno-stack-protector -fomit-frame-pointer -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-ident -ffunction-sections -fdata-sections"
c_asmflags := "-Oz -march=rv64i -mabi=lp64 -mcmodel=medany -msmall-data-limit=0 -ffreestanding -fno-builtin -fno-stack-protector -fomit-frame-pointer -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-ident -ffunction-sections -fdata-sections -fverbose-asm"
ldflags := "-Ttext=0x80000000 -e _start -march=rv64i -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none -Wl,--strip-all"
ldflags_debug := "-Ttext=0x80000000 -e _start -march=rv64i -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none"

hex0_bin:
  mkdir -p {{build_dir}}
  ./scripts/hex0_to_bin.sh baremetal/hex0.hex0 {{build_dir}}/hex0.bin

test: test_full_chain

test_full_chain: hex0_bin
  bash -euxo pipefail -c '\
    mkdir -p {{build_dir}}; \
    rm -f {{build_dir}}/full_chain_derzforth.out {{build_dir}}/full_chain_derzforth.ok; \
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
      cat baremetal/riscv64_defs.M1 {{derzforth_m1_src}}; \
      printf "\x04"; \
      printf "\nfoo\nkey emit\nA\nbye\n"; \
    ) | timeout "${TIMEOUT_FULL_CHAIN:-20.0s}" qemu-system-riscv64-purecap -nographic -monitor none -serial stdio -machine virt -bios none -kernel {{build_dir}}/hex0.bin > {{build_dir}}/full_chain_derzforth.out 2>/dev/null || status=$?; \
    [[ "$status" -eq 0 ]]; \
    grep -Fqx " ok" {{build_dir}}/full_chain_derzforth.out; \
    grep -Fqx " ?" {{build_dir}}/full_chain_derzforth.out; \
    grep -Fqx "A ok" {{build_dir}}/full_chain_derzforth.out; \
    touch {{build_dir}}/full_chain_derzforth.ok \
  '

debug_hex0:
  bash -euxo pipefail -c '\
    mkdir -p {{build_dir}}; \
    {{as}} {{asflags}} baremetal/GAS/hex0.s -o {{build_dir}}/hex0.o; \
    {{cc}} {{ldflags_debug}} {{build_dir}}/hex0.o -o {{build_dir}}/hex0.debug.elf; \
    rm -f qemu-dbg.in qemu-dbg.out; \
    mkfifo qemu-dbg.in qemu-dbg.out; \
    exec qemu-system-riscv64-purecap -nographic -monitor none -serial pipe:qemu-dbg -machine virt -bios none -kernel {{build_dir}}/hex0.debug.elf -gdb tcp::1234 \
  '

derzforth_elf:
  mkdir -p {{build_dir}}
  {{cc}} {{ldflags}} {{derzforth_src}} -o {{derzforth_elf}}

run_derzforth: derzforth_elf
  exec qemu-system-riscv64-purecap -nographic -monitor none -serial stdio -machine virt -bios none -kernel {{derzforth_elf}}

test_derzforth: derzforth_elf
  bash -euxo pipefail -c '\
    mkdir -p {{build_dir}}; \
    rm -f {{build_dir}}/derzforth.out {{build_dir}}/derzforth.ok; \
    status=0; \
    printf "\nfoo\nkey emit\nA\nbye\n" | timeout "${TIMEOUT_DERZFORTH:-5.0s}" qemu-system-riscv64-purecap -nographic -monitor none -serial stdio -machine virt -bios none -kernel {{derzforth_elf}} > {{build_dir}}/derzforth.out 2>/dev/null || status=$?; \
    [[ "$status" -eq 0 ]]; \
    grep -Fqx " ok" {{build_dir}}/derzforth.out; \
    grep -Fqx " ?" {{build_dir}}/derzforth.out; \
    grep -Fqx "A ok" {{build_dir}}/derzforth.out; \
    touch {{build_dir}}/derzforth.ok \
  '

test_derzforth_m1: test_full_chain

clean:
  rm -rf {{build_dir}}
