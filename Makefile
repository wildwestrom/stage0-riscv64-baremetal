AS := riscv64-none-elf-as
CC := riscv64-none-elf-gcc
OBJCOPY := riscv64-none-elf-objcopy

ASFLAGS := -march=rv64i_zifencei -mabi=lp64
LDFLAGS := -T baremetal.ld -march=rv64i_zifencei -mabi=lp64 -nostdlib -static

QEMU_TIMEOUT := 1s

BUILD_DIR := build
SOURCES := hex0.s echo.s

OBJS := $(SOURCES:%.s=$(BUILD_DIR)/%.o)
ELFS := $(SOURCES:%.s=$(BUILD_DIR)/%.elf)
BINS := $(SOURCES:%.s=$(BUILD_DIR)/%.bin)
HEX0S := $(SOURCES:%.s=$(BUILD_DIR)/%.hex0)

.PHONY: all clean test_echo test_hex0

all: $(HEX0S)

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/%.o: %.s | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD_DIR)/%.elf: $(BUILD_DIR)/%.o baremetal.ld
	$(CC) $(LDFLAGS) $< -o $@

$(BUILD_DIR)/%.bin: $(BUILD_DIR)/%.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD_DIR)/%.hex0: $(BUILD_DIR)/%.bin
	xxd -p $< | tr -d '\n' > $@

# This is meant to automate testing the hex binaries.
test_hex0: $(BUILD_DIR)/echo.ok $(BUILD_DIR)/hex0_echo.ok

# Run only the echo test program.
test_echo: $(BUILD_DIR)/echo.ok

# This tests the echo program which is just supposed to echo each character back with a newline.
$(BUILD_DIR)/echo.out: $(BUILD_DIR)/echo.bin | $(BUILD_DIR)
	{ sleep 0.5; printf 'test'; } | timeout $(QEMU_TIMEOUT) qemu-system-riscv64 -nographic -monitor none -serial stdio -machine virt -kernel $(BUILD_DIR)/echo.bin > $@ 2>&1 || true

# Now we see if the test program echoed the correct sequence.
$(BUILD_DIR)/echo.ok: $(BUILD_DIR)/echo.out
	out=$$(grep -x '[tes]' $< | tr -d '\n'); [ "$$out" = test ]
	touch $@

# This is more complicated.
# From the previous test above, we know that the test program is working.
# This test tests the test program via hex0, ensuring that hex0 is working.
$(BUILD_DIR)/hex0_echo.out: $(BUILD_DIR)/echo.ok $(BUILD_DIR)/echo.hex0 $(BUILD_DIR)/hex0.bin | $(BUILD_DIR)
# There's a race condition where qemu might not be ready to read input, so we sleep.
	{ sleep 0.5; cat $(BUILD_DIR)/echo.hex0; printf '\x04'; printf 'test\n'; } | timeout $(QEMU_TIMEOUT) qemu-system-riscv64 -nographic -monitor none -serial stdio -machine virt -kernel $(BUILD_DIR)/hex0.bin > $@ 2>&1 || true

# We should get the exact same result as the previous test.
$(BUILD_DIR)/hex0_echo.ok: $(BUILD_DIR)/hex0_echo.out
	out=$$(grep -x '[tes]' $< | tr -d '\n'); [ "$$out" = test ]
	touch $@

clean:
	rm -f $(BUILD_DIR)/*

