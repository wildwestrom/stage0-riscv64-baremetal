#!/usr/bin/env python3
"""Generate four-line per-instruction commentary for a hex0 source file."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

REGISTER_NAMES = [
    "zero",
    "ra",
    "sp",
    "gp",
    "tp",
    "t0",
    "t1",
    "t2",
    "s0",
    "s1",
    "a0",
    "a1",
    "a2",
    "a3",
    "a4",
    "a5",
    "a6",
    "a7",
    "s2",
    "s3",
    "s4",
    "s5",
    "s6",
    "s7",
    "s8",
    "s9",
    "s10",
    "s11",
    "t3",
    "t4",
    "t5",
    "t6",
]

INSTRUCTION_RE = re.compile(
    r"^(?P<indent>\s*)(?P<bytes>[0-9A-Fa-f]{2}(?:\s+[0-9A-Fa-f]{2}){3})(?P<trailing>\s*(?:[#;].*)?)$"
)
LABEL_RE = re.compile(r"^(?P<indent>\s*#\s*[^#;]+:)\s*$")


def sign_extend(value: int, bits: int) -> int:
    sign_bit = 1 << (bits - 1)
    return (value ^ sign_bit) - sign_bit


def format_signed(value: int) -> str:
    if value < 0:
        return str(value)
    if value < 10:
        return str(value)
    return f"0x{value:X}"


def reg_name(index: int) -> str:
    return REGISTER_NAMES[index]


def asm_reg_name(index: int) -> str:
    if index == 0:
        return "x0"
    return reg_name(index)


def field_reg(index: int) -> str:
    return f"{index}({asm_reg_name(index)})"


def grouped_binary_bytes(word: int) -> str:
    return " ".join(f"{byte:08b}" for byte in word.to_bytes(4, byteorder="big"))


def format_hex(value: int, bits: int = 32) -> str:
    return f"0x{value & ((1 << bits) - 1):X}"


def decode_u(word: int, _address: int, opcode: int) -> dict[str, object]:
    imm20 = (word >> 12) & 0xFFFFF
    rd = (word >> 7) & 0x1F
    mnemonic = {0x17: "auipc", 0x37: "lui"}.get(opcode, "u-unknown")
    return {
        "type": "U",
        "mnemonic": mnemonic,
        "rd_index": rd,
        "upper_value": sign_extend(imm20 << 12, 32),
        "fields": [
            f"imm[31:12]=0x{imm20:X}",
            f"rd={field_reg(rd)}",
            f"opcode=0x{opcode:02X}",
        ],
        "decoded": f"{mnemonic} {asm_reg_name(rd)}, 0x{imm20:X}",
    }


def decode_i(word: int, _address: int, opcode: int) -> dict[str, object]:
    imm12_raw = (word >> 20) & 0xFFF
    imm12 = sign_extend(imm12_raw, 12)
    rs1 = (word >> 15) & 0x1F
    funct3 = (word >> 12) & 0x7
    rd = (word >> 7) & 0x1F
    mnemonic = "i-unknown"
    decoded = "i-unknown"
    if opcode == 0x13:
        if funct3 == 0b000:
            mnemonic = "addi"
            decoded = (
                f"addi {asm_reg_name(rd)}, {asm_reg_name(rs1)}, {format_signed(imm12)}"
            )
        elif funct3 == 0b111:
            mnemonic = "andi"
            decoded = f"andi {asm_reg_name(rd)}, {asm_reg_name(rs1)}, 0x{imm12_raw:X}"
        elif funct3 == 0b001:
            shamt = (word >> 20) & 0x3F
            mnemonic = "slli"
            decoded = f"slli {asm_reg_name(rd)}, {asm_reg_name(rs1)}, {shamt}"
    elif opcode == 0x1B:
        if funct3 == 0b000:
            mnemonic = "addiw"
            decoded = (
                f"addiw {asm_reg_name(rd)}, {asm_reg_name(rs1)}, {format_signed(imm12)}"
            )
    elif opcode == 0x03:
        mnemonic = {
            0b000: "lb",
            0b001: "lh",
            0b010: "lw",
            0b011: "ld",
            0b100: "lbu",
            0b101: "lhu",
            0b110: "lwu",
        }.get(funct3, "load-unknown")
        decoded = f"{mnemonic} {asm_reg_name(rd)}, {format_signed(imm12)}({asm_reg_name(rs1)})"
    elif opcode == 0x67 and funct3 == 0b000:
        mnemonic = "jalr"
        decoded = (
            f"jalr {asm_reg_name(rd)}, {asm_reg_name(rs1)}, {format_signed(imm12)}"
        )
    return {
        "type": "I",
        "mnemonic": mnemonic,
        "rd_index": rd,
        "rs1_index": rs1,
        "imm": imm12,
        "fields": [
            f"imm[11:0]=0x{imm12_raw:X}",
            f"rs1={field_reg(rs1)}",
            f"f3=0b{funct3:03b}",
            f"rd={field_reg(rd)}",
            f"opcode=0x{opcode:02X}",
        ],
        "decoded": decoded,
    }


def decode_r(word: int, opcode: int) -> dict[str, object]:
    funct7 = (word >> 25) & 0x7F
    rs2 = (word >> 20) & 0x1F
    rs1 = (word >> 15) & 0x1F
    funct3 = (word >> 12) & 0x7
    rd = (word >> 7) & 0x1F
    decoded = "r-unknown"
    if opcode == 0x33 and funct3 == 0b000 and funct7 == 0:
        decoded = f"add {asm_reg_name(rd)}, {asm_reg_name(rs1)}, {asm_reg_name(rs2)}"
    return {
        "type": "R",
        "fields": [
            f"funct7=0b{funct7:07b}",
            f"rs2={field_reg(rs2)}",
            f"rs1={field_reg(rs1)}",
            f"f3=0b{funct3:03b}",
            f"rd={field_reg(rd)}",
            f"opcode=0x{opcode:02X}",
        ],
        "decoded": decoded,
    }


def decode_s(word: int, opcode: int) -> dict[str, object]:
    imm11_5 = (word >> 25) & 0x7F
    rs2 = (word >> 20) & 0x1F
    rs1 = (word >> 15) & 0x1F
    funct3 = (word >> 12) & 0x7
    imm4_0 = (word >> 7) & 0x1F
    imm12_raw = (imm11_5 << 5) | imm4_0
    imm12 = sign_extend(imm12_raw, 12)
    store_name = {
        0b000: "sb",
        0b001: "sh",
        0b010: "sw",
        0b011: "sd",
    }.get(funct3, "store-unknown")
    return {
        "type": "S",
        "fields": [
            f"imm[11:5]=0b{imm11_5:07b}",
            f"rs2={field_reg(rs2)}",
            f"rs1={field_reg(rs1)}",
            f"f3=0b{funct3:03b}",
            f"imm[4:0]=0b{imm4_0:05b}",
            f"opcode=0x{opcode:02X}",
        ],
        "decoded": f"{store_name} {asm_reg_name(rs2)}, {format_signed(imm12)}({asm_reg_name(rs1)})",
    }


def decode_b(word: int, address: int, opcode: int) -> dict[str, object]:
    imm12 = (word >> 31) & 0x1
    imm10_5 = (word >> 25) & 0x3F
    rs2 = (word >> 20) & 0x1F
    rs1 = (word >> 15) & 0x1F
    funct3 = (word >> 12) & 0x7
    imm4_1 = (word >> 8) & 0xF
    imm11 = (word >> 7) & 0x1
    immediate_raw = (imm12 << 12) | (imm11 << 11) | (imm10_5 << 5) | (imm4_1 << 1)
    immediate = sign_extend(immediate_raw, 13)
    target = (address + immediate) & 0xFFFFFFFF
    branch_name = {
        0b000: "beq",
        0b001: "bne",
        0b100: "blt",
        0b101: "bge",
        0b110: "bltu",
        0b111: "bgeu",
    }.get(funct3, "branch-unknown")
    return {
        "type": "B",
        "fields": [
            f"imm[12]=0b{imm12:b}",
            f"imm[10:5]=0b{imm10_5:06b}",
            f"rs2={field_reg(rs2)}",
            f"rs1={field_reg(rs1)}",
            f"f3=0b{funct3:03b}",
            f"imm[4:1]=0b{imm4_1:04b}",
            f"imm[11]=0b{imm11:b}",
            f"opcode=0x{opcode:02X}",
        ],
        "decoded": f"{branch_name} {asm_reg_name(rs1)}, {asm_reg_name(rs2)}, 0x{target:04X}",
    }


def decode_j(word: int, address: int, opcode: int) -> dict[str, object]:
    imm20 = (word >> 31) & 0x1
    imm10_1 = (word >> 21) & 0x3FF
    imm11 = (word >> 20) & 0x1
    imm19_12 = (word >> 12) & 0xFF
    rd = (word >> 7) & 0x1F
    immediate_raw = (imm20 << 20) | (imm19_12 << 12) | (imm11 << 11) | (imm10_1 << 1)
    immediate = sign_extend(immediate_raw, 21)
    target = (address + immediate) & 0xFFFFFFFF
    return {
        "type": "J",
        "fields": [
            f"imm[20]=0b{imm20:b}",
            f"imm[10:1]=0b{imm10_1:010b}",
            f"imm[11]=0b{imm11:b}",
            f"imm[19:12]=0x{imm19_12:X}",
            f"rd={field_reg(rd)}",
            f"opcode=0x{opcode:02X}",
        ],
        "decoded": f"jal {asm_reg_name(rd)}, 0x{target:04X}",
    }


def decode_instruction(word: int, address: int) -> dict[str, object]:
    opcode = word & 0x7F
    if opcode in {0x17, 0x37}:
        return decode_u(word, address, opcode)
    if opcode in {0x13, 0x1B, 0x03, 0x67}:
        return decode_i(word, address, opcode)
    if opcode == 0x33:
        return decode_r(word, opcode)
    if opcode == 0x23:
        return decode_s(word, opcode)
    if opcode == 0x63:
        return decode_b(word, address, opcode)
    if opcode == 0x6F:
        return decode_j(word, address, opcode)
    return {
        "type": "unknown",
        "fields": [f"raw=0x{word:08X}", f"opcode=0x{opcode:02X}"],
        "decoded": "unknown",
    }


def pair_note(
    first: dict[str, object],
    second: dict[str, object],
    first_address: int,
    second_address: int,
) -> str | None:
    if first.get("type") != "U" or second.get("type") != "I":
        return None
    if second.get("mnemonic") not in {"addi", "addiw"}:
        return None
    rd_index = first.get("rd_index")
    if rd_index != second.get("rd_index") or rd_index != second.get("rs1_index"):
        return None

    reg = asm_reg_name(int(rd_index))
    upper_value = int(first["upper_value"])
    low_value = int(second["imm"])
    pair_name = f"{first['mnemonic']}/{second['mnemonic']}"

    if first.get("mnemonic") == "auipc":
        final_value = (first_address + upper_value + low_value) & 0xFFFFFFFF
        return (
            f"# Combined intent at 0x{first_address:04X}-0x{second_address:04X}: "
            f"{pair_name} builds pc-relative {reg} = {format_hex(final_value)} "
            f"(PC + {format_hex(upper_value)} + {format_signed(low_value)})"
        )

    if first.get("mnemonic") == "lui":
        final_value = upper_value + low_value
        if second.get("mnemonic") == "addiw":
            final_value = sign_extend(final_value & 0xFFFFFFFF, 32)
        return (
            f"# Combined intent at 0x{first_address:04X}-0x{second_address:04X}: "
            f"{pair_name} builds {reg} = {format_hex(final_value, 64)} "
            f"({format_hex(upper_value)} + {format_signed(low_value)})"
        )

    return None


def annotate_instruction(line: str, address: int) -> list[str]:
    match = INSTRUCTION_RE.match(line)
    if match is None:
        return [line]
    byte_tokens = match.group("bytes").split()
    word = int.from_bytes(
        bytes(int(token, 16) for token in byte_tokens), byteorder="little"
    )
    decoded = decode_instruction(word, address)
    byte_text = " ".join(token.upper() for token in byte_tokens)
    fields_text = " ".join(f"[{field}]" for field in decoded["fields"])
    return [
        f"{match.group('indent')}# Instruction at 0x{address:04X}: {decoded['decoded']}",
        f"{match.group('indent')}# Hex (LE):  {byte_text}  →  Word: 0x{word:08X}",
        f"{match.group('indent')}# Binary: {grouped_binary_bytes(word)}",
        f"{match.group('indent')}# Fields: {fields_text}",
        f"{match.group('indent')}{match.group('bytes').upper()}",
    ]


def annotate_lines(lines: list[str], source_name: str) -> list[str]:
    decoded_instructions: list[tuple[int, int, str, dict[str, object]]] = []
    address = 0
    for index, line in enumerate(lines):
        instruction_match = INSTRUCTION_RE.match(line)
        if instruction_match is not None:
            byte_tokens = instruction_match.group("bytes").split()
            word = int.from_bytes(
                bytes(int(token, 16) for token in byte_tokens), byteorder="little"
            )
            decoded_instructions.append((index, address, instruction_match.group("indent"), decode_instruction(word, address)))
            address += 4

    pair_notes: dict[int, str] = {}
    for current, following in zip(decoded_instructions, decoded_instructions[1:]):
        current_index, current_address, current_indent, current_decoded = current
        next_index, next_address, _, next_decoded = following
        if any(
            LABEL_RE.match(line) or INSTRUCTION_RE.match(line)
            for line in lines[current_index + 1 : next_index]
        ):
            continue
        note = pair_note(current_decoded, next_decoded, current_address, next_address)
        if note is not None:
            pair_notes[current_index] = f"{current_indent}{note}"

    output: list[str] = []
    inserted_banner = False
    address = 0
    for index, line in enumerate(lines):
        if not inserted_banner and line.startswith("# hex0 -"):
            output.append(line)
            output.append("# This file is generated from baremetal/hex0_source.hex0.")
            output.append("# Regenerate it with: just annotate_hex0")
            inserted_banner = True
            continue
        label_match = LABEL_RE.match(line)
        if label_match is not None:
            output.append(f"{label_match.group('indent')} Address 0x{address:X}")
            continue
        instruction_match = INSTRUCTION_RE.match(line)
        if instruction_match is not None:
            if index in pair_notes:
                output.append(pair_notes[index])
            output.extend(annotate_instruction(line, address))
            output.append("")
            address += 4
            continue
        output.append(line)
    if not inserted_banner:
        output.insert(0, f"# Generated from {source_name}.")
        output.insert(1, "# Regenerate it with: just annotate_hex0")
    return output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=pathlib.Path, help="input hex0 file")
    parser.add_argument("output", type=pathlib.Path, help="annotated hex0 file")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_lines = args.source.read_text(encoding="utf-8").splitlines()
    annotated = annotate_lines(source_lines, str(args.source))
    args.output.write_text("\n".join(annotated) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
