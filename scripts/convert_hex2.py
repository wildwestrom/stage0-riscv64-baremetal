#!/usr/bin/env python3
"""Convert baremetal/M0.hex2 raw words into structured full hex2 format."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from dataclasses import dataclass


DEFINE_RE = re.compile(r"^DEFINE\s+([A-Za-z0-9_]+)\s+([.]?[0-9A-Fa-f]+)\b")
LABEL_RE = re.compile(r"^:(?P<label>[A-Za-z0-9_]+)\s*$")
WORD_RE = re.compile(r"^(?P<indent>\s*)(?P<word>[0-9A-Fa-f]{8})\s*$")
ENCODED_LINE_RE = re.compile(
    r"^(?P<indent>\s*)(?P<body>(?:\.[0-9A-Fa-f]{8}|[0-9A-Fa-f]{8}|[@$~!][A-Za-z0-9_+-]+)(?:\s+(?:\.[0-9A-Fa-f]{8}|[0-9A-Fa-f]{8}|[@$~!][A-Za-z0-9_+-]+))*)\s*$"
)
OLD_COMMENT_RE = re.compile(r"^\s*#")
ASM_LABEL_RE = re.compile(r"^(?P<label>[A-Za-z0-9_]+):\s*$")
ASM_INSN_RE = re.compile(
    r"^\s*(?P<mnemonic>[.A-Za-z0-9_]+)\b(?P<operands>[^#]*)?(?:#\s*(?P<comment>.*))?$"
)

REGISTER_ALIASES = [
    "ZERO",
    "RA",
    "SP",
    "GP",
    "TP",
    "T0",
    "T1",
    "T2",
    "S0",
    "S1",
    "A0",
    "A1",
    "A2",
    "A3",
    "A4",
    "A5",
    "A6",
    "A7",
    "S2",
    "S3",
    "S4",
    "S5",
    "S6",
    "S7",
    "S8",
    "S9",
    "S10",
    "S11",
    "T3",
    "T4",
    "T5",
    "T6",
]

I_OPS = {
    (0x13, 0b000, None): "ADDI",
    (0x13, 0b010, None): "SLTI",
    (0x13, 0b011, None): "SLTIU",
    (0x13, 0b100, None): "XORI",
    (0x13, 0b110, None): "ORI",
    (0x13, 0b111, None): "ANDI",
    (0x13, 0b001, 0x00): "SLLI",
    (0x13, 0b101, 0x00): "SRLI",
    (0x13, 0b101, 0x10): "SRAI",
    (0x1B, 0b000, None): "ADDIW",
    (0x1B, 0b001, 0x00): "SLLIW",
    (0x1B, 0b101, 0x00): "SRLIW",
    (0x1B, 0b101, 0x20): "SRAIW",
    (0x03, 0b000, None): "LB",
    (0x03, 0b001, None): "LH",
    (0x03, 0b010, None): "LW",
    (0x03, 0b011, None): "LD",
    (0x03, 0b100, None): "LBU",
    (0x03, 0b101, None): "LHU",
    (0x03, 0b110, None): "LWU",
    (0x67, 0b000, None): "JALR",
}

R_OPS = {
    (0x33, 0b000, 0x00): "ADD",
    (0x33, 0b000, 0x20): "SUB",
    (0x33, 0b001, 0x00): "SLL",
    (0x33, 0b010, 0x00): "SLT",
    (0x33, 0b011, 0x00): "SLTU",
    (0x33, 0b100, 0x00): "XOR",
    (0x33, 0b101, 0x00): "SRL",
    (0x33, 0b101, 0x20): "SRA",
    (0x33, 0b110, 0x00): "OR",
    (0x33, 0b111, 0x00): "AND",
    (0x3B, 0b000, 0x00): "ADDW",
    (0x3B, 0b000, 0x20): "SUBW",
    (0x3B, 0b001, 0x00): "SLLW",
    (0x3B, 0b101, 0x00): "SRLW",
    (0x3B, 0b101, 0x20): "SRAW",
}

S_OPS = {
    0b000: "SB",
    0b001: "SH",
    0b010: "SW",
    0b011: "SD",
}

B_OPS = {
    0b000: "BEQ",
    0b001: "BNE",
    0b100: "BLT",
    0b101: "BGE",
    0b110: "BLTU",
    0b111: "BGEU",
}

U_OPS = {0x17: "AUIPC", 0x37: "LUI"}


@dataclass
class Entry:
    kind: str
    raw: str
    address: int | None = None
    label: str | None = None
    word: int | None = None
    gas_comment: str = ""


def sign_extend(value: int, bits: int) -> int:
    sign_bit = 1 << (bits - 1)
    return (value ^ sign_bit) - sign_bit


def to_le_hex32(value: int) -> str:
    return f".{value.to_bytes(4, byteorder='little').hex().upper()}"


def imm_token(prefix: str, value: int) -> str:
    if value < 0:
        return f"{prefix}{value}"
    return f"{prefix}{value}"


def normalize_label(label: str) -> str:
    return label.strip()


def parse_defs(path: pathlib.Path) -> dict[str, dict[object, str]]:
    rd_names: dict[int, str] = {}
    rs1_names: dict[int, str] = {}
    rs2_names: dict[int, str] = {}
    opcodes: dict[str, str] = {}

    for line in path.read_text(encoding="utf-8").splitlines():
        match = DEFINE_RE.match(line)
        if match is None:
            continue
        name, value_text = match.groups()
        if value_text.startswith("."):
            value = int.from_bytes(bytes.fromhex(value_text[1:]), byteorder="little")
            if name.startswith("RD_"):
                reg = (value >> 7) & 0x1F
                rd_names.setdefault(reg, name)
            elif name.startswith("RS1_"):
                reg = (value >> 15) & 0x1F
                rs1_names.setdefault(reg, name)
            elif name.startswith("RS2_"):
                reg = (value >> 20) & 0x1F
                rs2_names.setdefault(reg, name)
            continue
        if len(value_text) == 8:
            opcodes.setdefault(name, value_text.upper())

    return {
        "rd": rd_names,
        "rs1": rs1_names,
        "rs2": rs2_names,
        "opcodes": opcodes,
    }


def parse_gas(path: pathlib.Path) -> tuple[list[str], list[str]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    header_lines: list[str] = []
    header_started = False
    instruction_comments: list[str] = []

    for line in lines:
        stripped = line.strip()
        if stripped == "_start:":
            break
        if stripped.startswith("# Bare metal M0 stage payload."):
            header_started = True
        if header_started and stripped.startswith("#"):
            header_lines.append("; " + stripped[1:].strip())

    for line in lines:
        match = ASM_INSN_RE.match(line)
        if match is None:
            continue
        mnemonic = match.group("mnemonic")
        if mnemonic is None:
            continue
        if mnemonic.startswith("."):
            continue
        if ASM_LABEL_RE.match(line):
            continue
        comment = (match.group("comment") or "").strip()
        instruction_comments.append(comment)

    return header_lines, instruction_comments


def parse_m0(path: pathlib.Path) -> tuple[list[Entry], dict[str, int], int]:
    entries: list[Entry] = []
    labels: dict[str, int] = {}
    address = 0

    for line in path.read_text(encoding="utf-8").splitlines():
        label_match = LABEL_RE.match(line)
        if label_match is not None:
            label = normalize_label(label_match.group("label"))
            labels[label] = address
            entries.append(Entry(kind="label", raw=line, label=label, address=address))
            continue
        word_match = WORD_RE.match(line)
        encoded_match = ENCODED_LINE_RE.match(line)
        if word_match is not None or encoded_match is not None:
            body = (word_match.group("word") if word_match is not None else encoded_match.group("body"))
            entries.append(
                Entry(
                    kind="instruction",
                    raw=line,
                    address=address,
                    word=None if word_match is None else int.from_bytes(bytes.fromhex(body), byteorder="little"),
                )
            )
            entries[-1].raw = body
            address += 4
            continue
        if OLD_COMMENT_RE.match(line):
            entries.append(Entry(kind="old_comment", raw=line))
            continue
        entries.append(Entry(kind="other", raw=line))

    for entry in entries:
        if entry.kind != "instruction" or entry.word is not None:
            continue
        if entry.address is None:
            raise AssertionError("instruction missing address")
        entry.word = encode_instruction_tokens(entry.raw, entry.address, labels)

    return entries, labels, address


def encode_instruction_tokens(body: str, address: int, labels: dict[str, int]) -> int:
    tokens = body.split()
    word = 0
    for token in tokens:
        if token.startswith("."):
            word |= int.from_bytes(bytes.fromhex(token[1:]), byteorder="little")
        elif re.fullmatch(r"[0-9A-Fa-f]{8}", token):
            word |= int.from_bytes(bytes.fromhex(token), byteorder="little")

    opcode = word & 0x7F
    for token in tokens:
        if token.startswith("@") and token[1:] in labels:
            if opcode != 0x63:
                raise ValueError(f"unexpected @label on opcode 0x{opcode:02X}: {body}")
            word |= branch_imm_bits(labels[token[1:]] - address)
        elif token.startswith("$") and token[1:] in labels:
            if opcode != 0x6F:
                raise ValueError(f"unexpected $label on opcode 0x{opcode:02X}: {body}")
            word |= jal_imm_bits(labels[token[1:]] - address)
    return word


def parse_instruction(word: int, pc: int) -> dict[str, object]:
    opcode = word & 0x7F
    rd = (word >> 7) & 0x1F
    funct3 = (word >> 12) & 0x7
    rs1 = (word >> 15) & 0x1F
    rs2 = (word >> 20) & 0x1F
    funct7 = (word >> 25) & 0x7F

    if opcode in U_OPS:
        imm = sign_extend(word & 0xFFFFF000, 32)
        return {"type": "U", "mnemonic": U_OPS[opcode], "rd": rd, "imm": imm}
    if opcode == 0x6F:
        imm20 = (word >> 31) & 0x1
        imm10_1 = (word >> 21) & 0x3FF
        imm11 = (word >> 20) & 0x1
        imm19_12 = (word >> 12) & 0xFF
        raw = (imm20 << 20) | (imm19_12 << 12) | (imm11 << 11) | (imm10_1 << 1)
        imm = sign_extend(raw, 21)
        return {"type": "J", "mnemonic": "JAL", "rd": rd, "imm": imm, "target": pc + imm}
    if opcode == 0x63:
        imm12 = (word >> 31) & 0x1
        imm10_5 = (word >> 25) & 0x3F
        imm4_1 = (word >> 8) & 0xF
        imm11 = (word >> 7) & 0x1
        raw = (imm12 << 12) | (imm11 << 11) | (imm10_5 << 5) | (imm4_1 << 1)
        imm = sign_extend(raw, 13)
        mnemonic = B_OPS.get(funct3)
        if mnemonic is None:
            raise ValueError(f"unknown B instruction: 0x{word:08X}")
        return {
            "type": "B",
            "mnemonic": mnemonic,
            "rs1": rs1,
            "rs2": rs2,
            "imm": imm,
            "target": pc + imm,
        }
    if opcode == 0x23:
        imm = ((word >> 25) << 5) | rd
        imm = sign_extend(imm, 12)
        mnemonic = S_OPS.get(funct3)
        if mnemonic is None:
            raise ValueError(f"unknown S instruction: 0x{word:08X}")
        return {"type": "S", "mnemonic": mnemonic, "rs1": rs1, "rs2": rs2, "imm": imm}
    if opcode in {0x13, 0x1B, 0x03, 0x67}:
        imm = sign_extend(word >> 20, 12)
        key = (opcode, funct3, None)
        if opcode == 0x13 and funct3 in {0b001, 0b101}:
            key = (opcode, funct3, (word >> 26) & 0x3F)
        elif opcode == 0x1B and funct3 in {0b001, 0b101}:
            key = (opcode, funct3, funct7)
        mnemonic = I_OPS.get(key)
        if mnemonic is None:
            raise ValueError(f"unknown I instruction: 0x{word:08X}")
        return {
            "type": "I",
            "mnemonic": mnemonic,
            "rd": rd,
            "rs1": rs1,
            "rs2": rs2,
            "imm": imm,
        }
    if opcode in {0x33, 0x3B}:
        mnemonic = R_OPS.get((opcode, funct3, funct7))
        if mnemonic is None:
            raise ValueError(f"unknown R instruction: 0x{word:08X}")
        return {
            "type": "R",
            "mnemonic": mnemonic,
            "rd": rd,
            "rs1": rs1,
            "rs2": rs2,
        }
    if word == 0x00000073:
        return {"type": "SYS", "mnemonic": "ECALL"}
    if word == 0x00100073:
        return {"type": "SYS", "mnemonic": "EBREAK"}
    raise ValueError(f"unsupported instruction word: 0x{word:08X}")


def store_imm_bits(imm: int) -> int:
    imm12 = imm & 0xFFF
    return ((imm12 & 0xFE0) << 20) | ((imm12 & 0x1F) << 7)


def branch_imm_bits(imm: int) -> int:
    imm13 = imm & 0x1FFF
    return (
        ((imm13 >> 12) & 0x1) << 31
        | ((imm13 >> 5) & 0x3F) << 25
        | ((imm13 >> 1) & 0xF) << 8
        | ((imm13 >> 11) & 0x1) << 7
    )


def jal_imm_bits(imm: int) -> int:
    imm21 = imm & 0x1FFFFF
    return (
        ((imm21 >> 20) & 0x1) << 31
        | ((imm21 >> 1) & 0x3FF) << 21
        | ((imm21 >> 11) & 0x1) << 20
        | ((imm21 >> 12) & 0xFF) << 12
    )


def gas_comment_suffix(comment: str) -> str:
    if not comment:
        return ""
    return f" ; {comment}"


def render_instruction(
    decoded: dict[str, object],
    defs: dict[str, dict[object, str]],
    address_to_label: dict[int, str],
    gas_comment: str,
) -> tuple[str, str]:
    rd_names = defs["rd"]
    rs1_names = defs["rs1"]
    rs2_names = defs["rs2"]
    opcodes = defs["opcodes"]

    mnemonic = str(decoded["mnemonic"])
    comment_tokens: list[str] = []
    hex_tokens: list[str] = []

    def add_rd(reg: int) -> None:
        if reg != 0:
            comment_tokens.append(rd_names[reg])
            hex_tokens.append(to_le_hex32(reg << 7))

    def add_rs1(reg: int) -> None:
        if reg != 0:
            comment_tokens.append(rs1_names[reg])
            hex_tokens.append(to_le_hex32(reg << 15))

    def add_rs2(reg: int) -> None:
        if reg != 0:
            comment_tokens.append(rs2_names[reg])
            hex_tokens.append(to_le_hex32(reg << 20))

    dtype = str(decoded["type"])
    final_mnemonic = mnemonic

    if dtype == "SYS":
        comment_tokens.append(mnemonic)
        hex_tokens.append(opcodes[mnemonic])
        return (
            "    # " + " ".join(comment_tokens) + gas_comment_suffix(gas_comment),
            "    " + " ".join(hex_tokens),
        )

    if dtype == "R":
        add_rd(int(decoded["rd"]))
        add_rs1(int(decoded["rs1"]))
        add_rs2(int(decoded["rs2"]))
    elif dtype == "I":
        rd = int(decoded["rd"])
        rs1 = int(decoded["rs1"])
        imm = int(decoded["imm"])
        if mnemonic == "JALR" and rd == 0 and rs1 == 1 and imm == 0:
            comment_tokens.append("RS1_RA")
            comment_tokens.append("JALR")
            hex_tokens.append(to_le_hex32(1 << 15))
            hex_tokens.append(opcodes["JALR"])
            return (
                "    # " + " ".join(comment_tokens) + gas_comment_suffix(gas_comment),
                "    " + " ".join(hex_tokens),
            )
        if mnemonic == "ADDI" and imm == 0:
            final_mnemonic = "NOP" if rd == 0 and rs1 == 0 else ("ADDI" if rs1 == 0 else "MV")
            add_rd(rd)
            add_rs1(rs1)
            comment_tokens.append(final_mnemonic)
            hex_tokens.append(opcodes["ADDI"])
            return (
                "    # " + " ".join(comment_tokens) + gas_comment_suffix(gas_comment),
                "    " + " ".join(hex_tokens),
            )
        add_rd(rd)
        add_rs1(rs1)
        if mnemonic in {"SLLI", "SRLI", "SRAI", "SLLIW", "SRLIW", "SRAIW"}:
            shamt = int(decoded["imm"]) & (0x3F if mnemonic in {"SLLI", "SRLI", "SRAI"} else 0x1F)
            if shamt < 32:
                comment_tokens.append(f"RS2_X{shamt}")
            else:
                comment_tokens.append(imm_token("!", shamt))
            hex_tokens.append(to_le_hex32((int(decoded["imm"]) & 0xFFF) << 20))
        else:
            if imm != 0:
                comment_tokens.append(imm_token("!", imm))
                hex_tokens.append(to_le_hex32((imm & 0xFFF) << 20))
    elif dtype == "S":
        add_rs1(int(decoded["rs1"]))
        add_rs2(int(decoded["rs2"]))
        imm = int(decoded["imm"])
        if imm != 0:
            comment_tokens.append(imm_token("@" if imm > 0 else "!", imm))
            hex_tokens.append(to_le_hex32(store_imm_bits(imm)))
    elif dtype == "B":
        rs1 = int(decoded["rs1"])
        rs2 = int(decoded["rs2"])
        target = int(decoded["target"])
        label = address_to_label.get(target)
        if label is None:
            raise ValueError(f"no label for branch target 0x{target:08X}")
        if mnemonic == "BEQ" and rs2 == 0:
            final_mnemonic = "BEQZ"
            add_rs1(rs1)
        elif mnemonic == "BNE" and rs2 == 0:
            final_mnemonic = "BNEZ"
            add_rs1(rs1)
        elif mnemonic == "BLT" and rs2 == 0:
            final_mnemonic = "BLTZ"
            add_rs1(rs1)
        else:
            add_rs1(rs1)
            add_rs2(rs2)
        comment_tokens.append(f"@{label}")
        hex_tokens.append(f"@{label}")
    elif dtype == "U":
        add_rd(int(decoded["rd"]))
        imm = int(decoded["imm"])
        if imm != 0:
            comment_tokens.append(f"~0x{imm & 0xFFFFFFFF:X}")
            hex_tokens.append(to_le_hex32(imm & 0xFFFFF000))
    elif dtype == "J":
        add_rd(int(decoded["rd"]))
        target = int(decoded["target"])
        label = address_to_label.get(target)
        if label is None:
            raise ValueError(f"no label for jal target 0x{target:08X}")
        comment_tokens.append(f"${label}")
        hex_tokens.append(f"${label}")
    else:
        raise ValueError(f"unknown decoded type: {dtype}")

    comment_tokens.append(final_mnemonic)
    base_name = mnemonic if final_mnemonic not in {"NOP", "MV", "BEQZ", "BNEZ", "BLTZ"} else {
        "NOP": "ADDI",
        "MV": "ADDI",
        "BEQZ": "BEQ",
        "BNEZ": "BNE",
        "BLTZ": "BLT",
    }[final_mnemonic]
    hex_tokens.append(opcodes[base_name])
    return (
        "    # " + " ".join(comment_tokens) + gas_comment_suffix(gas_comment),
        "    " + " ".join(hex_tokens),
    )


def render(
    entries: list[Entry],
    labels: dict[str, int],
    defs: dict[str, dict[object, str]],
    header_lines: list[str],
    gas_comments: list[str],
) -> str:
    address_to_label = {address: label for label, address in labels.items()}
    instruction_entries = [entry for entry in entries if entry.kind == "instruction"]
    if len(instruction_entries) != len(gas_comments):
        raise ValueError(
            f"GAS/M0.s instruction count {len(gas_comments)} does not match M0.hex2 count {len(instruction_entries)}"
        )
    for entry, gas_comment in zip(instruction_entries, gas_comments):
        entry.gas_comment = gas_comment

    out: list[str] = []
    inserted_header = False
    skip_todo = False
    seen_first_label = False

    for entry in entries:
        if entry.kind == "label":
            seen_first_label = True

        if entry.kind == "old_comment":
            stripped = entry.raw.strip()
            if stripped == "# TODO:":
                skip_todo = True
                continue
            if skip_todo:
                if stripped.startswith("#   - "):
                    continue
                skip_todo = False
            if stripped.startswith("##"):
                out.append(entry.raw)
                if not inserted_header and "Keep the GAS source authoritative" in entry.raw:
                    out.append("")
                    out.extend(header_lines)
                    out.append("")
                    inserted_header = True
                continue
            continue

        if skip_todo:
            if entry.kind == "other" and not entry.raw.strip():
                continue
            skip_todo = False

        if not seen_first_label and entry.kind == "other":
            stripped = entry.raw.strip()
            if stripped.startswith(";") or stripped == "":
                continue

        if entry.kind == "instruction":
            if entry.word is None:
                raise AssertionError("instruction missing word")
            decoded = parse_instruction(entry.word, entry.address or 0)
            comment_line, hex_line = render_instruction(
                decoded,
                defs,
                address_to_label,
                entry.gas_comment,
            )
            out.append(comment_line)
            out.append(hex_line)
            continue

        out.append(entry.raw)

    return "\n".join(out) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument(
        "--defs",
        type=pathlib.Path,
        default=pathlib.Path("baremetal/riscv64_defs.M1"),
    )
    parser.add_argument(
        "--gas",
        type=pathlib.Path,
        default=pathlib.Path("baremetal/GAS/M0.s"),
    )
    args = parser.parse_args()

    defs = parse_defs(args.defs)
    entries, labels, _ = parse_m0(args.source)
    header_lines, gas_comments = parse_gas(args.gas)
    sys.stdout.write(render(entries, labels, defs, header_lines, gas_comments))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
