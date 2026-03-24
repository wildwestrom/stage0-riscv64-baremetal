set shell := ["bash", "-euo", "pipefail", "-c"]

repo_root := justfile_directory()
build_dir := join(repo_root, "build")
baremetal_dir := join(repo_root, "baremetal")
scripts_dir := join(repo_root, "scripts")
prototype_dir := join(baremetal_dir, "high_level_prototypes")
as := require("riscv64-none-elf-as")
cc := require("riscv64-none-elf-gcc")
host_cc := require("cc")
objcopy := require("riscv64-none-elf-objcopy")
python := require("python3")
sha256sum := require("sha256sum")
timeout := require("timeout")
qemu := require("qemu-system-riscv64-purecap")
qemu_flags := "-nographic -monitor none -machine virt -bios none -m 24M"
asflags := "-march=rv64im -mabi=lp64"
host_cflags := "-Oz -U_FORTIFY_SOURCE -g -DSYSTEM_POSIX=1"
ldflags := "-Ttext=0x80000000 -e _start -march=rv64im -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none -Wl,--strip-all"
ldflags_debug := "-Ttext=0x80000000 -e _start -march=rv64im -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none"
pass := f"echo {{GREEN}}{{BOLD}}PASS{{NORMAL}}; exit 0"
fail := f"echo {{RED}}{{BOLD}}FAIL{{NORMAL}}; exit 1"

_build_dir:
    mkdir -p {{ build_dir }}
as0_selfhost_harness_source := join(prototype_dir, "as0_selfhost_harness.c")
as0_source := join(prototype_dir, "as0.c")
as0_stage_source := join(baremetal_dir, "GAS", "as0.s")
as0_stage0_obj := join(build_dir, "as0-stage0.o")
as0_stage0_elf := join(build_dir, "as0-stage0.elf")
as0_stage0_bin := join(build_dir, "as0-stage0.bin")
as0_stage2_bin := join(build_dir, "as0-stage2.bin")
as0_host_ref := join(build_dir, "as0-host-ref")

_build_as0_stage0: _build_dir
    {{ as }} {{ asflags }} {{ as0_stage_source }} -o {{ as0_stage0_obj }}
    {{ cc }} {{ ldflags }} {{ as0_stage0_obj }} -o {{ as0_stage0_elf }}
    {{ objcopy }} -O binary {{ as0_stage0_elf }} {{ as0_stage0_bin }}

_build_as0_host_ref: _build_dir
    {{ host_cc }} {{ host_cflags }} -I {{ prototype_dir }} {{ as0_selfhost_harness_source }} {{ as0_source }} -o {{ as0_host_ref }}

hex0_source := join(baremetal_dir, "hex0.hex0")
hex0_bin_path := join(build_dir, without_extension(file_name(hex0_source)) + ".bin")
hex0_to_bin_script := join(scripts_dir, "hex0_to_bin.sh")

_hex0_bin: _build_dir
    {{ hex0_to_bin_script }} {{ hex0_source }} {{ hex0_bin_path }}

hex1_source := join(baremetal_dir, "hex1.hex0")
annotate_hex_script := join(scripts_dir, "annotate_hex0.py")
translate_riscv_tests_script := join(scripts_dir, "translate_riscv_tests.py")
riscv_tests_dir := join(repo_root, "reference", "riscv-tests", "isa", "rv64ui")
riscv_test_subset := "add addi and andi or ori xor xori sub slt slti sltu sltiu"

[private]
annotate source: _build_dir
    {{ python }} {{ annotate_hex_script }} {{ source }} {{ join(build_dir, file_stem(source) + "_annotated." + extension(source)) }}

annotate_hex0: (annotate hex0_source)

annotate_hex1: (annotate hex1_source)

hex2_source := join(baremetal_dir, "hex2.hex1")
m0_hex2_source := join(baremetal_dir, "M0.hex2")
riscv64_defs_source := join(baremetal_dir, "riscv64_defs.M1")
as0_m1_source := join(baremetal_dir, "as0.M1")
fullchain_as0_stage1_out := join(build_dir, "fullchain-as0-stage1.bin")

_test_full_chain_prep: _hex0_bin _build_as0_stage0
    rm -f {{ fullchain_as0_stage1_out }} {{ as0_stage2_bin }}

_run_full_chain out payload_a payload_b source:
    status=0; \
    ( \
      cat {{ hex0_source }}; \
      printf "\x04"; \
      cat {{ hex1_source }}; \
      printf "\x04"; \
      cat {{ hex2_source }}; \
      printf "\x04"; \
      cat {{ m0_hex2_source }}; \
      printf "\x04"; \
      cat "{{ payload_a }}" "{{ payload_b }}"; \
      printf "\x04"; \
      cat "{{ source }}"; \
      printf "\x04"; \
    ) | {{ timeout }} 20s {{ qemu }} {{ qemu_flags }} -serial stdio -kernel {{ hex0_bin_path }} > "{{ out }}" 2>/dev/null || status=$?; \
    if [[ "$status" -ne 0 && "$status" -ne 124 ]] || [[ ! -s "{{ out }}" ]]; then \
      {{ fail }}; \
    fi

_run_as0_kernel kernel source out:
    if ( cat "{{ source }}"; printf "\x04"; ) | {{ timeout }} 10s {{ qemu }} {{ qemu_flags }} -serial stdio -kernel "{{ kernel }}" > "{{ out }}" 2>/dev/null; then \
      :; \
    else \
      {{ fail }}; \
    fi

_test_full_chain_stage1: _test_full_chain_prep (_run_full_chain fullchain_as0_stage1_out riscv64_defs_source as0_m1_source as0_stage_source)

_test_full_chain_stage2: (_test_full_chain_stage1) (_run_as0_kernel fullchain_as0_stage1_out as0_stage_source as0_stage2_bin)

# This is the canonical test for the full bootstrap chain.
test: _test_full_chain_stage2
    hash_stage1=$({{ sha256sum }} {{ fullchain_as0_stage1_out }} | awk '{print $1}'); \
    hash_stage2=$({{ sha256sum }} {{ as0_stage2_bin }} | awk '{print $1}'); \
    if [[ "$hash_stage1" == "$hash_stage2" ]]; then \
      {{ pass }}; \
    else \
      {{ fail }}; \
    fi

test_as0_riscv_tests: _build_dir _build_as0_host_ref
    rm -f {{ join(build_dir, "riscv-tests-translate.log") }}; \
    for test_name in {{ riscv_test_subset }}; do \
      src={{ riscv_tests_dir }}/$test_name.S; \
      translated={{ build_dir }}/$test_name.as0.s; \
      oracle_obj={{ build_dir }}/$test_name.oracle.o; \
      oracle_bin={{ build_dir }}/$test_name.oracle.bin; \
      as0_bin={{ build_dir }}/$test_name.as0.bin; \
      if ! {{ python }} {{ translate_riscv_tests_script }} "$src" "$translated"; then {{ fail }}; fi; \
      if ! {{ as }} {{ asflags }} "$translated" -o "$oracle_obj"; then {{ fail }}; fi; \
      if ! {{ objcopy }} -O binary "$oracle_obj" "$oracle_bin"; then {{ fail }}; fi; \
      if ! {{ as0_host_ref }} < "$translated" > "$as0_bin"; then {{ fail }}; fi; \
      if ! cmp -s "$oracle_bin" "$as0_bin"; then \
        echo "mismatch: $test_name"; \
        {{ fail }}; \
      fi; \
    done; \
    {{ pass }}

hex0_debug_source := join(baremetal_dir, "GAS", "hex0.s")
hex0_obj := join(build_dir, "hex0.o")
hex0_debug_elf := join(build_dir, "hex0.debug.elf")

debug_hex0: _build_dir
    {{ as }} {{ asflags }} {{ hex0_debug_source }} -o {{ hex0_obj }}
    {{ cc }} {{ ldflags_debug }} {{ hex0_obj }} -o {{ hex0_debug_elf }}
    rm -f qemu-dbg.in qemu-dbg.out
    mkfifo qemu-dbg.in qemu-dbg.out
    {{ qemu }} {{ qemu_flags }} -serial pipe:qemu-dbg -kernel {{ hex0_debug_elf }} -gdb tcp::1234

clean:
    rm -rf {{ build_dir }}
