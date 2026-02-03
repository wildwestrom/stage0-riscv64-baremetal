#!/bin/sh
# hex0_to_bin.sh - Convert hex0 format to binary
# Usage: hex0_to_bin.sh input.hex0 output.bin
#
# hex0 format:
#   - Hex digits (0-9, a-f, A-F) are paired into bytes
#   - Comments start with # or ; and continue to end of line
#   - All other characters (whitespace, etc.) are ignored

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 input.hex0 output.bin" >&2
    exit 1
fi

# 1. Remove comments (# or ; to end of line)
# 2. Extract only hex digits
# 3. Convert hex to binary
sed 's/[#;].*//g' "$1" | tr -cd '0-9a-fA-F' | xxd -r -p > "$2"
