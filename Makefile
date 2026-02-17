AS := riscv64-none-elf-as
CC := riscv64-none-elf-gcc
OBJCOPY := riscv64-none-elf-objcopy

ASFLAGS := -march=rv64i -mabi=lp64
CFLAGS := -Oz -march=rv64i -mabi=lp64 -mcmodel=medany -ffreestanding -fno-builtin -fno-stack-protector -fomit-frame-pointer -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-ident -ffunction-sections -fdata-sections
C_ASMFLAGS := $(CFLAGS) -fverbose-asm
LDFLAGS := -Ttext=0x80000000 -e _start -march=rv64i -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none -Wl,--strip-all
LDFLAGS_DEBUG := -Ttext=0x80000000 -e _start -march=rv64i -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none

QEMU_TIMEOUT := 0.1s
QEMU_TIMEOUT_LONG := 0.5s

BUILD_DIR := build
HEX0_C := baremetal/high_level_prototype/stage0_monitor.c
C_SOURCES :=

C_OBJS := $(C_SOURCES:%.c=$(BUILD_DIR)/%.o)
C_ELFS := $(C_SOURCES:%.c=$(BUILD_DIR)/%.elf)
C_BINS := $(C_SOURCES:%.c=$(BUILD_DIR)/%.bin)
C_ASMS := $(C_SOURCES:%.c=$(BUILD_DIR)/%.s)
HEX0_ASM := $(BUILD_DIR)/stage0_monitor.s

.PHONY: all clean test_echo test_hex0 test_hex0_handwritten test_hex0_prototype test_hex1 test_hex2 prototypes debug force_test_echo force_test_hex0 force_test_hex1 force_test_hex2 verify_hex0

all: $(BUILD_DIR)/echo.bin $(BUILD_DIR)/hex0.bin

prototypes: $(C_BINS) $(C_ASMS) $(HEX0_ASM)

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/%.o: %.s | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD_DIR)/%.o: %.c
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.s: %.c
	mkdir -p $(dir $@)
	$(CC) $(C_ASMFLAGS) -S $< -o $@

$(BUILD_DIR)/stage0_monitor.s: $(HEX0_C) | $(BUILD_DIR)
	$(CC) $(C_ASMFLAGS) -S $< -o $@

$(BUILD_DIR)/%.o: $(HEX0_C) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/%.elf: $(BUILD_DIR)/%.o
	$(CC) $(LDFLAGS) $< -o $@

$(BUILD_DIR)/%.debug.elf: $(BUILD_DIR)/%.o
	$(CC) $(LDFLAGS_DEBUG) $< -o $@

$(BUILD_DIR)/%.bin: $(BUILD_DIR)/%.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD_DIR)/stage0_monitor.bin: $(BUILD_DIR)/stage0_monitor.s

# Special rule for stage0_monitor to use linker script that ensures _start comes first
$(BUILD_DIR)/stage0_monitor.elf: $(BUILD_DIR)/stage0_monitor.o baremetal/high_level_prototype/stage0_monitor.ld
	$(CC) -T baremetal/high_level_prototype/stage0_monitor.ld -e _start -march=rv64i -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none -Wl,--strip-all $< -o $@

$(BUILD_DIR)/stage0_monitor.debug.elf: $(BUILD_DIR)/stage0_monitor.o baremetal/high_level_prototype/stage0_monitor.ld
	$(CC) -T baremetal/high_level_prototype/stage0_monitor.ld -e _start -march=rv64i -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none $< -o $@

# Build echo from hex0
$(BUILD_DIR)/echo.bin: uart_echo/echo.hex0 hex0_to_bin.sh | $(BUILD_DIR)
	./hex0_to_bin.sh $< $@

$(BUILD_DIR)/echo.hex0: uart_echo/echo.hex0 | $(BUILD_DIR)
	cp $< $@

# Build hex0 from assembly (for comparison/debugging)
$(BUILD_DIR)/hex0.o: baremetal/GAS/hex0.s | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD_DIR)/hex0.elf: $(BUILD_DIR)/hex0.o
	$(CC) $(LDFLAGS) $< -o $@

# Build hex0 from hand-written hex0.hex0 using our converter script
$(BUILD_DIR)/hex0_handwritten.bin: baremetal/hex0.hex0 hex0_to_bin.sh | $(BUILD_DIR)
	./hex0_to_bin.sh $< $@

# Build hex1 from assembly
$(BUILD_DIR)/hex1.o: baremetal/GAS/hex1.s | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD_DIR)/hex1.elf: $(BUILD_DIR)/hex1.o
	$(CC) $(LDFLAGS) $< -o $@

# Build hex1 from hex1.hex0 using hex0 (assembled from .s)
$(BUILD_DIR)/hex1_from_hex0.bin: baremetal/hex1.hex0 $(BUILD_DIR)/hex0.bin | $(BUILD_DIR)
	{ cat $<; printf '\x04'; } | timeout $(QEMU_TIMEOUT) qemu-system-riscv64 -nographic -monitor none -serial stdio -machine virt -bios none -kernel $(BUILD_DIR)/hex0.bin 2>/dev/null | tail -c +1 > $@

# Verify that hex0.hex0 produces identical binary to assembly-generated hex0.bin
verify_hex0: $(BUILD_DIR)/hex0.bin $(BUILD_DIR)/hex0_handwritten.bin
	diff $^ && echo "hex0.hex0 matches hex0.s output"

$(BUILD_DIR)/%.hex0: $(BUILD_DIR)/%.bin
	xxd -p $< | tr -d '\n' > $@

# This tests the hand-written assembly hex0.
test_hex0: $(BUILD_DIR)/echo.ok $(BUILD_DIR)/hex0_echo.ok

# This tests the C prototype stage0_monitor.
test_hex0_prototype: $(BUILD_DIR)/echo.ok $(BUILD_DIR)/hex0_prototype_echo.ok $(HEX0_ASM)

# Run only the echo test program.
test_echo: $(BUILD_DIR)/echo.ok

# This tests the echo program which is just supposed to echo each character back with a newline.
$(BUILD_DIR)/echo.out: force_test_echo $(BUILD_DIR)/echo.bin | $(BUILD_DIR)
	printf 'test' | timeout $(QEMU_TIMEOUT) qemu-system-riscv64 -nographic -monitor none -serial stdio -machine virt -bios none -kernel $(BUILD_DIR)/echo.bin > $@ 2>&1 || true

# Now we see if the test program echoed the correct sequence.
$(BUILD_DIR)/echo.ok: $(BUILD_DIR)/echo.out
	grep -q 'test' $<
	touch $@

# This tests hex0 (assembly) loading itself, then using itself to load echo.
# This verifies that hex0 can bootstrap itself and then load other programs.
$(BUILD_DIR)/hex0_echo.out: force_test_hex0 $(BUILD_DIR)/hex0.hex0 $(BUILD_DIR)/echo.hex0 $(BUILD_DIR)/hex0.bin | $(BUILD_DIR)
	{ cat $(BUILD_DIR)/hex0.hex0; printf '\x04'; cat $(BUILD_DIR)/echo.hex0; printf '\x04'; printf 'test\n'; } | timeout $(QEMU_TIMEOUT) qemu-system-riscv64 -nographic -monitor none -serial stdio -machine virt -bios none -kernel $(BUILD_DIR)/hex0.bin > $@ 2>&1 || true

$(BUILD_DIR)/hex0_echo.ok: $(BUILD_DIR)/hex0_echo.out
	grep -q 'test' $<
	touch $@

# Test the hand-written hex0.hex0 directly (converted via hex0_to_bin.sh)
test_hex0_handwritten: $(BUILD_DIR)/echo.ok $(BUILD_DIR)/hex0_handwritten_echo.ok

# This tests hex0 (from hex0.hex0) loading itself, then using itself to load echo.
$(BUILD_DIR)/hex0_handwritten_echo.out: force_test_hex0 $(BUILD_DIR)/hex0.hex0 $(BUILD_DIR)/echo.hex0 $(BUILD_DIR)/hex0_handwritten.bin | $(BUILD_DIR)
	{ cat $(BUILD_DIR)/hex0.hex0; printf '\x04'; cat $(BUILD_DIR)/echo.hex0; printf '\x04'; printf 'test\n'; } | timeout $(QEMU_TIMEOUT) qemu-system-riscv64 -nographic -monitor none -serial stdio -machine virt -bios none -kernel $(BUILD_DIR)/hex0_handwritten.bin > $@ 2>&1 || true

$(BUILD_DIR)/hex0_handwritten_echo.ok: $(BUILD_DIR)/hex0_handwritten_echo.out
	grep -q 'test' $<
	touch $@

# This tests stage0_monitor (C) loading itself, then using itself to load echo.
# This verifies that the C prototype can bootstrap itself and then load other programs.
$(BUILD_DIR)/hex0_prototype_echo.out: force_test_hex0 $(BUILD_DIR)/stage0_monitor.hex0 $(BUILD_DIR)/echo.hex0 $(BUILD_DIR)/stage0_monitor.bin | $(BUILD_DIR)
	{ cat $(BUILD_DIR)/stage0_monitor.hex0; printf '\x04'; cat $(BUILD_DIR)/echo.hex0; printf '\x04'; printf 'test\n'; } | timeout $(QEMU_TIMEOUT) qemu-system-riscv64 -nographic -monitor none -serial stdio -machine virt -bios none -kernel $(BUILD_DIR)/stage0_monitor.bin > $@ 2>&1 || true

$(BUILD_DIR)/hex0_prototype_echo.ok: $(BUILD_DIR)/hex0_prototype_echo.out
	grep -q 'test' $<
	touch $@

# Test hex1: hex0.bin loads hex0.hex0, which loads hex1.hex0, which loads echo.hex1
test_hex1: $(BUILD_DIR)/hex1_echo.ok

$(BUILD_DIR)/hex1_echo.out: force_test_hex1 $(BUILD_DIR)/hex0.hex0 $(BUILD_DIR)/hex1.hex0 uart_echo/echo.hex1 $(BUILD_DIR)/hex0.bin | $(BUILD_DIR)
	(cat $(BUILD_DIR)/hex0.hex0; printf '\x04'; cat $(BUILD_DIR)/hex1.hex0; printf '\x04'; cat uart_echo/echo.hex1; printf '\x04'; printf 'test\n') | timeout $(QEMU_TIMEOUT_LONG) qemu-system-riscv64 -nographic -monitor none -serial stdio -machine virt -bios none -kernel $(BUILD_DIR)/hex0.bin > $@ 2>&1 || true

$(BUILD_DIR)/hex1_echo.ok: $(BUILD_DIR)/hex1_echo.out
	grep -q 'test' $<
	touch $@

force_test_hex1:
	rm -f $(BUILD_DIR)/hex1_echo.out $(BUILD_DIR)/hex1_echo.ok

# Build hex2 from assembly
$(BUILD_DIR)/hex2.o: baremetal/GAS/hex2.s | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD_DIR)/hex2.elf: $(BUILD_DIR)/hex2.o
	$(CC) $(LDFLAGS) $< -o $@

$(BUILD_DIR)/hex2.bin: $(BUILD_DIR)/hex2.elf
	$(OBJCOPY) -O binary $< $@

# Test full toolchain up to hex2:
# hex0.bin -> hex0.hex0 -> hex1.hex0 -> hex2.hex1 -> echo.hex2
test_hex2: $(BUILD_DIR)/hex2_echo.ok

$(BUILD_DIR)/hex2_echo.out: force_test_hex2 $(BUILD_DIR)/hex0.hex0 $(BUILD_DIR)/hex1.hex0 baremetal/hex2.hex1 uart_echo/echo.hex2 $(BUILD_DIR)/hex0.bin | $(BUILD_DIR)
	(cat $(BUILD_DIR)/hex0.hex0; printf '\x04'; cat $(BUILD_DIR)/hex1.hex0; printf '\x04'; cat baremetal/hex2.hex1; printf '\x04'; cat uart_echo/echo.hex2; printf '\x04'; printf 'test\n') | timeout 2s qemu-system-riscv64 -nographic -monitor none -serial stdio -machine virt -bios none -kernel $(BUILD_DIR)/hex0.bin > $@ 2>&1 || true

$(BUILD_DIR)/hex2_echo.ok: $(BUILD_DIR)/hex2_echo.out
	grep -q 'test' $<
	touch $@

force_test_hex2:
	rm -f $(BUILD_DIR)/hex2_echo.out $(BUILD_DIR)/hex2_echo.ok

debug_hex0: $(BUILD_DIR)/hex0.debug.elf
	rm -f qemu-dbg.in qemu-dbg.out
	mkfifo qemu-dbg.in qemu-dbg.out
	qemu-system-riscv64 -nographic -monitor none -serial pipe:qemu-dbg -machine virt -bios none -kernel $< -gdb tcp::1234

clean:
	rm -rf $(BUILD_DIR)

