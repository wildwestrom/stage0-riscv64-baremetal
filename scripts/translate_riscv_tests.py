#!/usr/bin/env python3

import argparse
import pathlib
import re
import sys


TEST_MACRO_RE = re.compile(r"^\s*(TEST_[A-Z0-9_]+)\s*\((.*)\)\s*;\s*$")


def split_args(text: str) -> list[str]:
    parts: list[str] = []
    current: list[str] = []
    depth = 0

    for ch in text:
        if ch == "," and depth == 0:
            parts.append("".join(current).strip())
            current = []
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        current.append(ch)

    tail = "".join(current).strip()
    if tail:
        parts.append(tail)
    return parts


def parse_int(text: str) -> int:
    return int(text, 0)


def sext_12(text: str) -> int:
    value = parse_int(text) & 0xFFF
    if value & 0x800:
        value -= 0x1000
    return value


def split_hi_lo(value: int) -> tuple[int, int]:
    lo = value & 0xFFF
    hi = value & ~0xFFF
    if lo >= 0x800:
        hi += 0x1000
        lo -= 0x1000
    return hi >> 12, lo


def emit_signed32_load(reg: str, value: int) -> list[str]:
    if -2048 <= value <= 2047:
        return [f"addi {reg}, x0, {value}"]

    hi, lo = split_hi_lo(value & 0xFFFFFFFF)
    if lo == 0:
        return [f"lui {reg}, {hi}"]
    return [f"lui {reg}, {hi}", f"addiw {reg}, {reg}, {lo}"]


def emit_load_imm(reg: str, value_text: str) -> list[str]:
    value = parse_int(value_text)
    if 0 <= value <= 0xFFFFFFFF:
        unsigned32 = value
        signed32 = ((unsigned32 + (1 << 31)) & 0xFFFFFFFF) - (1 << 31)
        lines = emit_signed32_load(reg, signed32)
        if unsigned32 > 0x7FFFFFFF:
            lines.extend([f"slli {reg}, {reg}, 32", f"srli {reg}, {reg}, 32"])
        return lines
    if value >= (1 << 63):
        value -= 1 << 64
    signed32 = ((value + (1 << 31)) & 0xFFFFFFFF) - (1 << 31)
    if value != signed32:
        raise ValueError(f"immediate out of signed-32 range for translator: {value_text}")
    return emit_signed32_load(reg, signed32)


def emit_rr_op(inst: str, val1: str, val2: str) -> list[str]:
    return [
        *emit_load_imm("x11", val1),
        *emit_load_imm("x12", val2),
        f"{inst} x14, x11, x12",
    ]


def emit_rr_src1_eq_dest(inst: str, val1: str, val2: str) -> list[str]:
    return [
        *emit_load_imm("x11", val1),
        *emit_load_imm("x12", val2),
        f"{inst} x11, x11, x12",
    ]


def emit_rr_src2_eq_dest(inst: str, val1: str, val2: str) -> list[str]:
    return [
        *emit_load_imm("x11", val1),
        *emit_load_imm("x12", val2),
        f"{inst} x12, x11, x12",
    ]


def emit_rr_src12_eq_dest(inst: str, val1: str) -> list[str]:
    return [
        *emit_load_imm("x11", val1),
        f"{inst} x11, x11, x11",
    ]


def emit_rr_dest_bypass(label: str, nops: str, inst: str, val1: str, val2: str) -> list[str]:
    return [
        *emit_load_imm("x4", "0"),
        f"{label}:",
        *emit_load_imm("x1", val1),
        *emit_load_imm("x2", val2),
        f"{inst} x14, x1, x2",
        *(["nop"] * parse_int(nops)),
        "addi x6, x14, 0",
        "addi x4, x4, 1",
        *emit_load_imm("x5", "2"),
        f"bne x4, x5, {label}",
    ]


def emit_rr_src12_bypass(
    label: str, src1_nops: str, src2_nops: str, inst: str, val1: str, val2: str
) -> list[str]:
    return [
        *emit_load_imm("x4", "0"),
        f"{label}:",
        *emit_load_imm("x1", val1),
        *(["nop"] * parse_int(src1_nops)),
        *emit_load_imm("x2", val2),
        *(["nop"] * parse_int(src2_nops)),
        f"{inst} x14, x1, x2",
        "addi x4, x4, 1",
        *emit_load_imm("x5", "2"),
        f"bne x4, x5, {label}",
    ]


def emit_rr_src21_bypass(
    label: str, src1_nops: str, src2_nops: str, inst: str, val1: str, val2: str
) -> list[str]:
    return [
        *emit_load_imm("x4", "0"),
        f"{label}:",
        *emit_load_imm("x2", val2),
        *(["nop"] * parse_int(src1_nops)),
        *emit_load_imm("x1", val1),
        *(["nop"] * parse_int(src2_nops)),
        f"{inst} x14, x1, x2",
        "addi x4, x4, 1",
        *emit_load_imm("x5", "2"),
        f"bne x4, x5, {label}",
    ]


def emit_rr_zero_src1(inst: str, val: str) -> list[str]:
    return [
        *emit_load_imm("x1", val),
        f"{inst} x2, x0, x1",
    ]


def emit_rr_zero_src2(inst: str, val: str) -> list[str]:
    return [
        *emit_load_imm("x1", val),
        f"{inst} x2, x1, x0",
    ]


def emit_rr_zero_src12(inst: str) -> list[str]:
    return [f"{inst} x1, x0, x0"]


def emit_rr_zero_dest(inst: str, val1: str, val2: str) -> list[str]:
    return [
        *emit_load_imm("x1", val1),
        *emit_load_imm("x2", val2),
        f"{inst} x0, x1, x2",
    ]


def emit_imm_op(inst: str, val1: str, imm: str) -> list[str]:
    return [
        *emit_load_imm("x13", val1),
        f"{inst} x14, x13, {sext_12(imm)}",
    ]


def emit_imm_src1_eq_dest(inst: str, val1: str, imm: str) -> list[str]:
    return [
        *emit_load_imm("x11", val1),
        f"{inst} x11, x11, {sext_12(imm)}",
    ]


def emit_imm_dest_bypass(label: str, nops: str, inst: str, val1: str, imm: str) -> list[str]:
    return [
        *emit_load_imm("x4", "0"),
        f"{label}:",
        *emit_load_imm("x1", val1),
        f"{inst} x14, x1, {sext_12(imm)}",
        *(["nop"] * parse_int(nops)),
        "addi x6, x14, 0",
        "addi x4, x4, 1",
        *emit_load_imm("x5", "2"),
        f"bne x4, x5, {label}",
    ]


def emit_imm_src1_bypass(label: str, nops: str, inst: str, val1: str, imm: str) -> list[str]:
    return [
        *emit_load_imm("x4", "0"),
        f"{label}:",
        *emit_load_imm("x1", val1),
        *(["nop"] * parse_int(nops)),
        f"{inst} x14, x1, {sext_12(imm)}",
        "addi x4, x4, 1",
        *emit_load_imm("x5", "2"),
        f"bne x4, x5, {label}",
    ]


def emit_imm_zero_src1(inst: str, imm: str) -> list[str]:
    return [f"{inst} x1, x0, {sext_12(imm)}"]


def emit_imm_zero_dest(inst: str, val1: str, imm: str) -> list[str]:
    return [
        *emit_load_imm("x1", val1),
        f"{inst} x0, x1, {sext_12(imm)}",
    ]


def translate_case(macro: str, args: list[str], case_id: int) -> list[str]:
    label = f".Ltest_{case_id}"
    if macro == "TEST_RR_OP":
        _, inst, _, val1, val2 = args
        return emit_rr_op(inst, val1, val2)
    if macro == "TEST_RR_SRC1_EQ_DEST":
        _, inst, _, val1, val2 = args
        return emit_rr_src1_eq_dest(inst, val1, val2)
    if macro == "TEST_RR_SRC2_EQ_DEST":
        _, inst, _, val1, val2 = args
        return emit_rr_src2_eq_dest(inst, val1, val2)
    if macro == "TEST_RR_SRC12_EQ_DEST":
        _, inst, _, val1 = args
        return emit_rr_src12_eq_dest(inst, val1)
    if macro == "TEST_RR_DEST_BYPASS":
        _, nops, inst, _, val1, val2 = args
        return emit_rr_dest_bypass(label, nops, inst, val1, val2)
    if macro == "TEST_RR_SRC12_BYPASS":
        _, src1_nops, src2_nops, inst, _, val1, val2 = args
        return emit_rr_src12_bypass(label, src1_nops, src2_nops, inst, val1, val2)
    if macro == "TEST_RR_SRC21_BYPASS":
        _, src1_nops, src2_nops, inst, _, val1, val2 = args
        return emit_rr_src21_bypass(label, src1_nops, src2_nops, inst, val1, val2)
    if macro == "TEST_RR_ZEROSRC1":
        _, inst, _, val = args
        return emit_rr_zero_src1(inst, val)
    if macro == "TEST_RR_ZEROSRC2":
        _, inst, _, val = args
        return emit_rr_zero_src2(inst, val)
    if macro == "TEST_RR_ZEROSRC12":
        _, inst, _ = args
        return emit_rr_zero_src12(inst)
    if macro == "TEST_RR_ZERODEST":
        _, inst, val1, val2 = args
        return emit_rr_zero_dest(inst, val1, val2)
    if macro == "TEST_IMM_OP":
        _, inst, _, val1, imm = args
        return emit_imm_op(inst, val1, imm)
    if macro == "TEST_IMM_SRC1_EQ_DEST":
        _, inst, _, val1, imm = args
        return emit_imm_src1_eq_dest(inst, val1, imm)
    if macro == "TEST_IMM_DEST_BYPASS":
        _, nops, inst, _, val1, imm = args
        return emit_imm_dest_bypass(label, nops, inst, val1, imm)
    if macro == "TEST_IMM_SRC1_BYPASS":
        _, nops, inst, _, val1, imm = args
        return emit_imm_src1_bypass(label, nops, inst, val1, imm)
    if macro == "TEST_IMM_ZEROSRC1":
        _, inst, _, imm = args
        return emit_imm_zero_src1(inst, imm)
    if macro == "TEST_IMM_ZERODEST":
        _, inst, val1, imm = args
        return emit_imm_zero_dest(inst, val1, imm)
    raise ValueError(f"unsupported macro {macro}")


def translate(path: pathlib.Path) -> str:
    lines = [
        ".text",
        "",
        f"# translated from {path.as_posix()}",
        "",
    ]
    case_id = 0

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        match = TEST_MACRO_RE.match(raw_line)
        if not match:
            continue

        macro = match.group(1)
        if macro == "TEST_PASSFAIL":
            continue

        args = split_args(match.group(2))
        lines.extend(translate_case(macro, args, case_id))
        lines.append("")
        case_id += 1

    if case_id == 0:
        raise ValueError(f"found no translatable test cases in {path}")

    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()

    try:
        translated = translate(args.input)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    args.output.write_text(translated, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
