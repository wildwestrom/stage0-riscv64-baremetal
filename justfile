set shell := ["bash", "-euo", "pipefail", "-c"]

repo_root := justfile_directory()
build_dir := join(repo_root, "build")
baremetal_dir := join(repo_root, "baremetal")
scripts_dir := join(repo_root, "scripts")
uart_echo_dir := join(repo_root, "uart_echo")

as := require("riscv64-none-elf-as")
cc := require("riscv64-none-elf-gcc")
objcopy := require("riscv64-none-elf-objcopy")
python := require("python3")
timeout := require("timeout")
qemu := require("qemu-system-riscv64-purecap")
qemu_flags := "-nographic -monitor none -machine virt -bios none -m 24M"

timeout_quick := env("TIMEOUT_QUICK", "1.0s")
timeout_full_chain := env("TIMEOUT_FULL_CHAIN", "5.0s")

asflags := "-march=rv64i -mabi=lp64"
asflags_m0 := "-march=rv64i -mabi=lp64 --defsym M0_HEAP_BASE=0x80100000 --defsym M0_INPUT_BASE=0x80200000 --defsym M0_STACK_TOP=0x80500000"
cflags := "-Oz -march=rv64i -mabi=lp64 -mcmodel=medany -msmall-data-limit=0 -ffreestanding -fno-builtin -fno-stack-protector -fomit-frame-pointer -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-ident -ffunction-sections -fdata-sections"
c_asmflags := "-Oz -march=rv64i -mabi=lp64 -mcmodel=medany -msmall-data-limit=0 -ffreestanding -fno-builtin -fno-stack-protector -fomit-frame-pointer -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-ident -ffunction-sections -fdata-sections -fverbose-asm"
ldflags := "-Ttext=0x80000000 -e _start -march=rv64i -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none -Wl,--strip-all"
ldflags_debug := "-Ttext=0x80000000 -e _start -march=rv64i -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none"
pass:= f"echo {{GREEN}}{{BOLD}}PASS{{NORMAL}}"
fail:= f"echo {{RED}}{{BOLD}}FAIL{{NORMAL}}"

build_dir:
	mkdir -p {{build_dir}}

hex0_source := join(baremetal_dir, "hex0.hex0")
hex0_bin_path := join(build_dir, without_extension(file_name(hex0_source)) + ".bin")
hex0_to_bin_script := join(scripts_dir, "hex0_to_bin.sh")

hex0_bin: build_dir
  {{hex0_to_bin_script}} {{hex0_source}} {{hex0_bin_path}}

hex1_source := join(baremetal_dir, "hex1.hex0")
annotate_hex_script := join(scripts_dir, "annotate_hex0.py")

[private]
annotate source: build_dir
  {{python}} {{annotate_hex_script}} {{source}} {{join(build_dir, file_stem(source) + "_annotated." + extension(source))}}

annotate_hex0: (annotate hex0_source)

annotate_hex1: (annotate hex1_source)

hex2_source := join(baremetal_dir, "hex2.hex1")
m0_hex2_source := join(baremetal_dir, "M0.hex2")
riscv64_defs_source := join(baremetal_dir, "riscv64_defs.M1")
echo_m1_source := join(uart_echo_dir, "echo.M1")
full_chain_out := join(build_dir, "full_chain.out")

# This is the canonical test for the full bootstrap chain
test: hex0_bin
  rm -f {{full_chain_out}};
  status=0;
  ( \
    cat {{hex0_source}}; \
    printf "\x04"; \
    cat {{hex1_source}}; \
    printf "\x04"; \
    cat {{hex2_source}}; \
    printf "\x04"; \
    cat {{m0_hex2_source}}; \
    printf "\x04"; \
    cat {{riscv64_defs_source}} {{echo_m1_source}}; \
    printf "\x04"; \
    printf "test"; \
  ) | {{timeout}} {{timeout_full_chain}} {{qemu}} {{qemu_flags}} -serial stdio -kernel {{hex0_bin_path}} > {{full_chain_out}} 2>/dev/null || status=$?; \
  if [[ "$status" -eq 0 || "$status" -eq 124 ]] && cmp -s {{full_chain_out}} <(printf "test"); then \
    {{pass}}; \
  else \
    {{fail}}; \
    exit 1; \
  fi

echo_c_source := join(uart_echo_dir, "echo.c")
echo_asm_source := join(uart_echo_dir, "echo.s")
echo_c_base := join(build_dir, "echo-c")
echo_c_obj := echo_c_base + ".o"
echo_c_bin := echo_c_base + ".bin"
echo_c_gcc_asm := join(build_dir, "echo-gcc.s")

test_echo_c: build_dir
  rm -rf {{echo_c_obj}} {{echo_c_bin}} {{echo_c_gcc_asm}} {{join(build_dir, "echo.o")}} {{join(build_dir, "echo.elf")}} {{join(build_dir, "echo.bin")}} {{join(build_dir, "echo.S")}}
  {{cc}} {{cflags}} {{ldflags}} {{echo_c_source}} -o {{echo_c_obj}}
  {{cc}} {{c_asmflags}} {{ldflags}} -S {{echo_c_source}} -o {{echo_c_gcc_asm}}
  {{objcopy}} -O binary {{echo_c_obj}} {{echo_c_bin}}
  rm -f {{echo_out}} {{join(build_dir, "echo_asm.out")}};
  status=0;
  ( printf "test"; ) | {{timeout}} {{timeout_quick}} {{qemu}} {{qemu_flags}} -serial stdio -kernel {{echo_c_bin}} > {{echo_out}} 2>/dev/null || status=$?; \
  if [[ "$status" -eq 0 || "$status" -eq 124 ]] && cmp -s {{echo_out}} <(printf "test"); then \
    {{pass}}; \
  else \
    {{fail}}; \
  exit 1; \
  fi

echo_asm_base := join(build_dir, "echo-asm")
echo_asm_obj := echo_asm_base + ".o"
echo_asm_elf := echo_asm_base + ".elf"
echo_asm_bin := echo_asm_base + ".bin"
echo_out := join(build_dir, "echo.out")

test_echo_asm: build_dir
  rm -rf {{echo_asm_obj}} {{echo_asm_elf}} {{echo_asm_bin}} {{join(build_dir, "echo.o")}} {{join(build_dir, "echo.elf")}} {{join(build_dir, "echo.bin")}} {{join(build_dir, "echo.S")}}
  {{as}} {{asflags}} {{echo_asm_source}} -o {{echo_asm_obj}}
  {{cc}} {{ldflags}} {{echo_asm_obj}} -o {{echo_asm_elf}}
  {{objcopy}} -O binary {{echo_asm_elf}} {{echo_asm_bin}}
  rm -f {{echo_out}} {{join(build_dir, "echo_asm.out")}};
  status=0;
  ( printf "test"; ) | {{timeout}} {{timeout_quick}} {{qemu}} {{qemu_flags}} -serial stdio -kernel {{echo_asm_bin}} > {{echo_out}} 2>/dev/null || status=$?; \
  if [[ "$status" -eq 0 || "$status" -eq 124 ]] && cmp -s {{echo_out}} <(printf "test"); then \
  {{pass}}; \
  else \
  {{fail}}; \
  exit 1; \
  fi

m0_asm_source := join(baremetal_dir, "GAS", "M0.s")
m0_obj := join(build_dir, "M0.o")
m0_elf := join(build_dir, "M0.elf")
m0_bin := join(build_dir, "M0.bin")

m0_prototype: build_dir
	{{as}} {{asflags_m0}} {{m0_asm_source}} -o {{m0_obj}}
	{{cc}} {{ldflags_debug}} {{m0_obj}} -o {{m0_elf}}
	{{objcopy}} -O binary {{m0_elf}} {{m0_bin}}

hex0_debug_source := join(baremetal_dir, "GAS", "hex0.s")
hex0_obj := join(build_dir, "hex0.o")
hex0_debug_elf := join(build_dir, "hex0.debug.elf")

debug_hex0: build_dir
  {{as}} {{asflags}} {{hex0_debug_source}} -o {{hex0_obj}}
  {{cc}} {{ldflags_debug}} {{hex0_obj}} -o {{hex0_debug_elf}}
  rm -f qemu-dbg.in qemu-dbg.out
  mkfifo qemu-dbg.in qemu-dbg.out
  {{qemu}} {{qemu_flags}} -serial pipe:qemu-dbg -kernel {{hex0_debug_elf}} -gdb tcp::1234

clean:
  rm -rf {{build_dir}}
