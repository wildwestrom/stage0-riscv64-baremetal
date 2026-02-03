AS := riscv64-none-elf-as
CC := riscv64-none-elf-gcc
OBJCOPY := riscv64-none-elf-objcopy

ASFLAGS := -march=rv64i -mabi=lp64
CFLAGS := -Oz -march=rv64i -mabi=lp64 -mcmodel=medany -ffreestanding -fno-builtin -fno-stack-protector -fomit-frame-pointer -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-ident -ffunction-sections -fdata-sections
C_ASMFLAGS := $(CFLAGS) -fverbose-asm
LDFLAGS := -Ttext=0x80000000 -e _start -march=rv64i -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none -Wl,--strip-all
LDFLAGS_DEBUG := -Ttext=0x80000000 -e _start -march=rv64i -mabi=lp64 -mcmodel=medany -nostdlib -static -Wl,--gc-sections -Wl,--build-id=none

QEMU_TIMEOUT := 0.1s

BUILD_DIR := build
SOURCES := echo.s
HEX0_C := stage0/high_level_prototype/stage0_monitor.c
C_SOURCES :=

OBJS := $(SOURCES:%.s=$(BUILD_DIR)/%.o)
ELFS := $(SOURCES:%.s=$(BUILD_DIR)/%.elf)
BINS := $(SOURCES:%.s=$(BUILD_DIR)/%.bin)
HEX0S := $(SOURCES:%.s=$(BUILD_DIR)/%.hex0)

C_OBJS := $(C_SOURCES:%.c=$(BUILD_DIR)/%.o)
C_ELFS := $(C_SOURCES:%.c=$(BUILD_DIR)/%.elf)
C_BINS := $(C_SOURCES:%.c=$(BUILD_DIR)/%.bin)
C_ASMS := $(C_SOURCES:%.c=$(BUILD_DIR)/%.s)
HEX0_ASM := $(BUILD_DIR)/stage0_monitor.s

.PHONY: all clean test_echo test_hex0 prototypes debug force_test_echo force_test_hex0

all: $(HEX0S)

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

$(BUILD_DIR)/hex0.o: stage0/hex0.s | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD_DIR)/hex0.elf: $(BUILD_DIR)/hex0.o
	$(CC) $(LDFLAGS) $< -o $@

$(BUILD_DIR)/%.hex0: $(BUILD_DIR)/%.bin
	xxd -p $< | tr -d '\n' > $@

# This is meant to automate testing the hex binaries.
test_hex0: $(BUILD_DIR)/echo.ok $(BUILD_DIR)/hex0_echo.ok $(HEX0_ASM)

# Run only the echo test program.
test_echo: $(BUILD_DIR)/echo.ok

# This tests the echo program which is just supposed to echo each character back with a newline.
$(BUILD_DIR)/echo.out: force_test_echo $(BUILD_DIR)/echo.bin | $(BUILD_DIR)
	printf 'test' | timeout $(QEMU_TIMEOUT) qemu-system-riscv64 -nographic -monitor none -serial stdio -machine virt -bios none -kernel $(BUILD_DIR)/echo.bin > $@ 2>&1 || true

# Now we see if the test program echoed the correct sequence.
$(BUILD_DIR)/echo.ok: $(BUILD_DIR)/echo.out
	out=$$(grep -x '[tes]' $< | tr -d '\n'); [ "$$out" = test ]
	touch $@

# This tests hex0 loading itself, then using itself to load echo.
# This verifies that hex0 can bootstrap itself and then load other programs.
$(BUILD_DIR)/hex0_echo.out: force_test_hex0 $(BUILD_DIR)/hex0.hex0 $(BUILD_DIR)/echo.hex0 $(BUILD_DIR)/hex0.bin | $(BUILD_DIR)
	{ cat $(BUILD_DIR)/hex0.hex0; printf '\x04'; cat $(BUILD_DIR)/echo.hex0; printf '\x04'; printf 'test\n'; } | timeout $(QEMU_TIMEOUT) qemu-system-riscv64 -nographic -monitor none -serial stdio -machine virt -bios none -kernel $(BUILD_DIR)/hex0.bin > $@ 2>&1 || true

$(BUILD_DIR)/hex0_echo.ok: $(BUILD_DIR)/hex0_echo.out
	out=$$(grep -x '[tes]' $< | tr -d '\n'); [ "$$out" = test ]
	touch $@

debug_hex0: $(BUILD_DIR)/hex0.debug.elf
	rm -f qemu-dbg.in qemu-dbg.out
	mkfifo qemu-dbg.in qemu-dbg.out
	qemu-system-riscv64 -nographic -monitor none -serial pipe:qemu-dbg -machine virt -bios none -kernel $< -gdb tcp::1234

clean:
	rm -rf $(BUILD_DIR)

