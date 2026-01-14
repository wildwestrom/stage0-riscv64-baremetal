build_dir := "build"

build:
	mkdir -p {{build_dir}}
	riscv64-none-elf-as -march=rv64i -mabi=lp64 stage0.s -o {{build_dir}}/stage0.o
	riscv64-none-elf-gcc -T baremetal.ld -march=rv64i -mabi=lp64 -nostdlib -static -o {{build_dir}}/stage0.elf {{build_dir}}/stage0.o
	riscv64-none-elf-objcopy -O binary {{build_dir}}/stage0.elf {{build_dir}}/stage0.bin

run: build
	qemu-system-riscv64 -nographic -monitor none -serial stdio -machine virt -kernel {{build_dir}}/stage0.bin

clean:
	rm -r {{build_dir}}