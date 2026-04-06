#!/usr/bin/env bash
binary_file=$1

riscv64-none-elf-objdump -d "$binary_file" | awk '
/^[ ]+[0-9a-f]+:[ \t]+[0-9a-f]+/ {
    match($0, /^[ ]+([0-9a-f]+):[ \t]+([0-9a-f]+)[ \t]+(.*)$/, m)
    addr = m[1]
    bytes_hex = m[2]
    instr = m[3]

    gsub(/ /, "", bytes_hex)
    le = ""
    for (i = length(bytes_hex); i >= 1; i -= 2) {
        le = le toupper(substr(bytes_hex, i - 1, 2)) " "
    }
    le = substr(le, 1, length(le) - 1)
    printf "%s  %s  %s\n", addr, le, instr
}
'
