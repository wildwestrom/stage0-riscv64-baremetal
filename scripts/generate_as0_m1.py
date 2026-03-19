#!/usr/bin/env python3

"""Regenerate `baremetal/as0.M1` from the reference GAS source.

This is intentionally not wired into `just`. Keep it as a last-resort helper
for analysis, regeneration, or auditing when the checked-in artifact needs to
be compared against `baremetal/GAS/as0.s`.
"""

from __future__ import annotations

import argparse
import ast
import re
from dataclasses import dataclass
from pathlib import Path

HEADER = """## Copyright (C) 2026 Christian Westrom
## This file is part of stage0.
##
## stage0 is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## stage0 is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with stage0.  If not, see <http://www.gnu.org/licenses/>.

# Self-hosting assembler payload for M0.
# Source of truth for the bootstrap path; `baremetal/GAS/as0.s` is kept as
# a reference listing input with matching intent comments.
#
# Concatenate `baremetal/riscv64_defs.M1` immediately before this file before
# sending it to M0.
"""

REG_ALIASES = {
    "zero": "X0",
    "ra": "RA",
    "sp": "SP",
    "gp": "GP",
    "tp": "TP",
    "fp": "FP",
}

R_OPS = {
    "add": "ADD",
    "sub": "SUB",
    "and": "AND",
    "or": "OR",
    "xor": "XOR",
    "slt": "SLT",
    "sltu": "SLTU",
    "mul": "MUL",
    "subw": "SUBW",
}

I_OPS = {
    "addi": "ADDI",
    "andi": "ANDI",
    "slli": "SLLI",
    "srli": "SRLI",
    "sltiu": "SLTIU",
    "addiw": "ADDIW",
}

LOAD_OPS = {
    "lbu": "LBU",
    "ld": "LD",
    "lw": "LW",
    "lwu": "LWU",
}

STORE_OPS = {
    "sb": "SB",
    "sd": "SD",
    "sw": "SW",
}

BRANCH_OPS = {
    "beq": "BEQ",
    "bne": "BNE",
    "blt": "BLT",
    "bltu": "BLTU",
    "bge": "BGE",
    "bgeu": "BGEU",
}


@dataclass
class SourceLine:
    label: str | None
    body: str
    comment: str


def split_comment(line: str) -> tuple[str, str]:
    in_string = False
    quote = ""
    escaped = False

    for index, ch in enumerate(line):
        if in_string:
            if escaped:
                escaped = False
                continue
            if ch == "\\":
                escaped = True
                continue
            if ch == quote:
                in_string = False
            continue

        if ch in {'"', "'"}:
            in_string = True
            quote = ch
            continue

        if ch == "#":
            return line[:index].rstrip(), line[index + 1 :].strip()

    return line.rstrip(), ""


def parse_source_line(raw: str) -> SourceLine:
    body, comment = split_comment(raw)
    if not body.strip():
        return SourceLine(None, "", comment)

    stripped = body.strip()
    if stripped.endswith(":"):
        return SourceLine(stripped[:-1], "", comment)

    label = None
    if ":" in stripped:
        candidate, rest = stripped.split(":", 1)
        if candidate and re.fullmatch(r"[A-Za-z_.$][A-Za-z0-9_.$]*", candidate):
            label = candidate
            stripped = rest.strip()

    return SourceLine(label, stripped, comment)


def split_operands(rest: str) -> list[str]:
    operands: list[str] = []
    current: list[str] = []
    depth = 0
    in_string = False
    quote = ""

    for ch in rest:
        if in_string:
            current.append(ch)
            if ch == quote:
                in_string = False
            continue

        if ch in {'"', "'"}:
            in_string = True
            quote = ch
            current.append(ch)
            continue

        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1

        if ch == "," and depth == 0:
            operands.append("".join(current).strip())
            current = []
            continue

        current.append(ch)

    tail = "".join(current).strip()
    if tail:
        operands.append(tail)
    return operands


def parse_expr(expr: str) -> ast.AST:
    return ast.parse(expr, mode="eval").body


def eval_ast(node: ast.AST, defines: dict[str, int]) -> int:
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub)):
        left = eval_ast(node.left, defines)
        right = eval_ast(node.right, defines)
        return left + right if isinstance(node.op, ast.Add) else left - right
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
        return -eval_ast(node.operand, defines)
    if isinstance(node, ast.Constant) and isinstance(node.value, int):
        return node.value
    if isinstance(node, ast.Constant) and isinstance(node.value, str) and len(node.value) == 1:
        return ord(node.value)
    if isinstance(node, ast.Name):
        return defines[node.id]
    raise ValueError(f"unsupported expression: {ast.unparse(node)}")


def eval_expr(expr: str, defines: dict[str, int]) -> int:
    expr = expr.strip()
    return eval_ast(parse_expr(expr), defines)


def format_define_value(value: int) -> str:
    if value < 0:
        return str(value)
    return f"0x{value:X}"


def reg_alias(name: str) -> str:
    lowered = name.strip().lower()
    if lowered in REG_ALIASES:
        return REG_ALIASES[lowered]
    if re.fullmatch(r"x([0-9]|[12][0-9]|3[01])", lowered):
        return lowered.upper()
    return lowered.upper()


def rd(reg: str) -> str:
    return f"RD_{reg_alias(reg)}"


def rs1(reg: str) -> str:
    return f"RS1_{reg_alias(reg)}"


def rs2(reg: str) -> str:
    return f"RS2_{reg_alias(reg)}"


def format_imm(value: int) -> str:
    if value < 0:
        return str(value)
    if value >= 10:
        return f"0x{value:X}"
    return str(value)


def imm_token(prefix: str, expr: str, defines: dict[str, int], *, allow_label: bool = False) -> str:
    text = expr.strip()
    if allow_label and re.fullmatch(r"[A-Za-z_.$][A-Za-z0-9_.$]*", text) and text not in defines:
        return f"{prefix}{text}"
    value = eval_expr(text, defines)
    return f"{prefix}{format_imm(value)}"


def maybe_prefix(prefix: str, expr: str, defines: dict[str, int], *, allow_label: bool = False) -> list[str]:
    if allow_label and re.fullmatch(r"[A-Za-z_.$][A-Za-z0-9_.$]*", expr.strip()) and expr.strip() not in defines:
        return [imm_token(prefix, expr, defines, allow_label=True)]
    value = eval_expr(expr, defines)
    if value == 0:
        return []
    return [f"{prefix}{format_imm(value)}"]


def parse_mem_operand(operand: str) -> tuple[str, str]:
    match = re.fullmatch(r"(.+?)\(([^()]+)\)", operand.strip())
    if not match:
        raise ValueError(f"invalid memory operand: {operand}")
    return match.group(1).strip(), match.group(2).strip()


def m1_line(tokens: list[str], comment: str) -> str:
    body = " ".join(tokens)
    if comment:
        return f"    {body}  # {comment}"
    return f"    {body}"


def quote_string_token(text: str) -> str:
    return ast.literal_eval(repr(text))  # type: ignore[arg-type]


def emit_dword(expr: str, comment: str, defines: dict[str, int]) -> str:
    value = eval_expr(expr, defines) & ((1 << 64) - 1)
    raw = value.to_bytes(8, "little").hex().upper()
    token = "'" + raw + "'"
    return m1_line([token], comment)


def emit_string(expr: str, comment: str) -> str:
    return m1_line([expr.strip()], comment)


def expand_instruction(mnemonic: str, operands: list[str], comment: str, defines: dict[str, int]) -> list[str]:
    op = mnemonic.lower()

    if op in R_OPS:
        rd_reg, rs1_reg, rs2_reg = operands
        return [m1_line([rd(rd_reg), rs1(rs1_reg), rs2(rs2_reg), R_OPS[op]], comment)]

    if op in I_OPS:
        rd_reg, rs1_reg, imm = operands
        tokens = maybe_prefix("!", imm, defines) + [rd(rd_reg), rs1(rs1_reg), I_OPS[op]]
        return [m1_line(tokens, comment)]

    if op in LOAD_OPS:
        rd_reg, mem = operands
        offset, base = parse_mem_operand(mem)
        tokens = maybe_prefix("!", offset, defines) + [rd(rd_reg), rs1(base), LOAD_OPS[op]]
        return [m1_line(tokens, comment)]

    if op in STORE_OPS:
        rs2_reg, mem = operands
        offset, base = parse_mem_operand(mem)
        tokens = maybe_prefix("@", offset, defines) + [rs1(base), rs2(rs2_reg), STORE_OPS[op]]
        return [m1_line(tokens, comment)]

    if op in BRANCH_OPS:
        rs1_reg, rs2_reg, label = operands
        return [m1_line([imm_token("@", label, defines, allow_label=True), rs1(rs1_reg), rs2(rs2_reg), BRANCH_OPS[op]], comment)]

    if op == "jalr":
        if len(operands) == 1:
            return [m1_line([rd("ra"), rs1(operands[0]), "JALR"], comment)]
        if len(operands) == 2:
            rd_reg, mem = operands
            offset, base = parse_mem_operand(mem)
            tokens = maybe_prefix("!", offset, defines) + [rd(rd_reg), rs1(base), "JALR"]
            return [m1_line(tokens, comment)]
        raise ValueError(f"unsupported jalr operands: {operands}")

    if op == "lui":
        rd_reg, imm = operands
        return [m1_line([imm_token("~", imm, defines, allow_label=True), rd(rd_reg), "LUI"], comment)]

    if op == "j":
        return [m1_line([imm_token("$", operands[0], defines, allow_label=True), rd("x0"), "JAL"], comment)]

    if op == "call":
        target = operands[0]
        return [
            m1_line([imm_token("~", target, defines, allow_label=True), rd("ra"), "AUIPC"], comment),
            m1_line([imm_token("!", target, defines, allow_label=True), rd("ra"), rs1("ra"), "JALR"], ""),
        ]

    if op == "la":
        rd_reg, target = operands
        return [
            m1_line([imm_token("~", target, defines, allow_label=True), rd(rd_reg), "AUIPC"], comment),
            m1_line([imm_token("!", target, defines, allow_label=True), rd(rd_reg), rs1(rd_reg), "ADDI"], ""),
        ]

    if op == "li":
        rd_reg, expr = operands
        value = eval_expr(expr, defines)
        if -2048 <= value <= 2047:
            tokens = maybe_prefix("!", expr, defines) + [rd(rd_reg), rs1("x0"), "ADDI"]
            return [m1_line(tokens, comment)]
        return [
            m1_line([imm_token("~", expr, defines), rd(rd_reg), "LUI"], comment),
            m1_line(maybe_prefix("!", expr, defines) + [rd(rd_reg), rs1(rd_reg), "ADDIW"], ""),
        ]

    if op == "mv":
        rd_reg, rs_reg = operands
        return [m1_line([rd(rd_reg), rs1(rs_reg), "MV"], comment)]

    if op == "ret":
        return [m1_line(["RETURN"], comment)]

    if op == "neg":
        rd_reg, rs_reg = operands
        return [m1_line([rd(rd_reg), rs1("x0"), rs2(rs_reg), "SUB"], comment)]

    if op == "bgt":
        left, right, label = operands
        return [m1_line([imm_token("@", label, defines, allow_label=True), rs1(right), rs2(left), "BLT"], comment)]

    if op == "ble":
        left, right, label = operands
        return [m1_line([imm_token("@", label, defines, allow_label=True), rs1(right), rs2(left), "BGE"], comment)]

    if op == "bgtu":
        left, right, label = operands
        return [m1_line([imm_token("@", label, defines, allow_label=True), rs1(right), rs2(left), "BLTU"], comment)]

    if op == "bleu":
        left, right, label = operands
        return [m1_line([imm_token("@", label, defines, allow_label=True), rs1(right), rs2(left), "BGEU"], comment)]

    if op == "bgtz":
        reg, label = operands
        return [m1_line([imm_token("@", label, defines, allow_label=True), rs1("x0"), rs2(reg), "BLT"], comment)]

    if op == "blez":
        reg, label = operands
        return [m1_line([imm_token("@", label, defines, allow_label=True), rs1("x0"), rs2(reg), "BGE"], comment)]

    if op == "bgez":
        reg, label = operands
        return [m1_line([imm_token("@", label, defines, allow_label=True), rs1(reg), rs2("x0"), "BGE"], comment)]

    if op == "bltz":
        reg, label = operands
        return [m1_line([imm_token("@", label, defines, allow_label=True), rs1(reg), rs2("x0"), "BLT"], comment)]

    if op == "ecall":
        return [m1_line(["ECALL"], comment)]

    if op == "ebreak":
        return [m1_line(["EBREAK"], comment)]

    raise ValueError(f"unsupported mnemonic: {mnemonic}")


def render_m1(source_text: str) -> str:
    lines = source_text.splitlines()
    defines: dict[str, int] = {}
    parsed = [parse_source_line(raw) for raw in lines]

    for entry in parsed:
        if not entry.body.startswith(".equ "):
            continue
        rest = entry.body[5:].strip()
        name, expr = [part.strip() for part in rest.split(",", 1)]
        defines[name] = eval_expr(expr, defines)

    out_lines = [HEADER.rstrip(), ""]

    for entry in parsed:
        if entry.label:
            out_lines.append(f":{entry.label}")

        body = entry.body
        comment = entry.comment
        if not body:
            continue

        if body.startswith(".global") or body == ".text":
            if comment:
                out_lines.append(f"# {comment}")
            continue

        if body.startswith(".equ "):
            rest = body[5:].strip()
            name, _expr = [part.strip() for part in rest.split(",", 1)]
            define_line = f"DEFINE {name} {format_define_value(defines[name])}"
            if comment:
                out_lines.append(f"{define_line}  # {comment}")
            else:
                out_lines.append(define_line)
            continue

        if body.startswith(".dword "):
            out_lines.append(emit_dword(body[7:].strip(), comment, defines))
            continue

        if body.startswith(".string "):
            out_lines.append(emit_string(body[8:].strip(), comment))
            continue

        parts = body.split(None, 1)
        mnemonic = parts[0]
        operands = split_operands(parts[1] if len(parts) > 1 else "")
        out_lines.extend(expand_instruction(mnemonic, operands, comment, defines))

    return "\n".join(out_lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        default="baremetal/GAS/as0.s",
        type=Path,
        help="Reference GAS source with preserved intent comments.",
    )
    parser.add_argument(
        "--output",
        default="baremetal/as0.M1",
        type=Path,
        help="Destination M1 artifact path.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit non-zero if the output would change.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    source = repo_root / args.source
    output = repo_root / args.output
    rendered = render_m1(source.read_text())

    if args.check:
        return 0 if output.exists() and output.read_text() == rendered else 1

    output.write_text(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
