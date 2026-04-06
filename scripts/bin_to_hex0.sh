#!/bin/sh
# bin_to_hex0.sh - Convert binary to hex0 format (raw hex, no comments)
# Usage: bin_to_hex0.sh input.bin output.hex0
#
# Output format:
#   - Uppercase hex byte pairs, 4 per line (one RISC-V instruction)
#   - Little-endian byte order (already correct in the binary)

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 input.bin output.hex0" >&2
    exit 1
fi

xxd -p "$1" | tr -d '\n' | fold -w 8 | while IFS= read -r line; do
    upper=$(echo "$line" | fold -w 2 | tr 'a-f' 'A-F' | tr '\n' ' ' | sed 's/ $//')
    echo "$upper"
done > "$2"
