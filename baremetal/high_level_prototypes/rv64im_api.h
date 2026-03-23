#ifndef BAREMETAL_HIGH_LEVEL_PROTOTYPE_RV64IM_API_H
#define BAREMETAL_HIGH_LEVEL_PROTOTYPE_RV64IM_API_H

#include <stdint.h>

/* Emit RV64I instruction words by combining a fixed opcode/match value with the
 * variable register or immediate fields for a given instruction format.
 *
 * The assembler should usually traffic in the `(format, match)` pair directly.
 * The per-instruction macros below exist so the prototype can keep readable
 * call sites without paying for one function body per mnemonic.
 */

enum rv64i_format {
  RV64I_FORMAT_FIXED,
  RV64I_FORMAT_R,
  RV64I_FORMAT_I,
  RV64I_FORMAT_I_SHAMT6,
  RV64I_FORMAT_I_SHAMT5,
  RV64I_FORMAT_S,
  RV64I_FORMAT_B,
  RV64I_FORMAT_U,
  RV64I_FORMAT_J,
  RV64I_FORMAT_FENCE,
};

uint32_t rv64i_emit(enum rv64i_format format, uint32_t match, int arg0, int arg1,
                    int arg2, int arg3, int arg4);

enum {
  RV64I_MATCH_ADD = 0x00000033u,
  RV64I_MATCH_ADDI = 0x00000013u,
  RV64I_MATCH_ADDIW = 0x0000001bu,
  RV64I_MATCH_ADDW = 0x0000003bu,
  RV64I_MATCH_AND = 0x00007033u,
  RV64I_MATCH_ANDI = 0x00007013u,
  RV64I_MATCH_AUIPC = 0x00000017u,
  RV64I_MATCH_BEQ = 0x00000063u,
  RV64I_MATCH_BGE = 0x00005063u,
  RV64I_MATCH_BGEU = 0x00007063u,
  RV64I_MATCH_BLT = 0x00004063u,
  RV64I_MATCH_BLTU = 0x00006063u,
  RV64I_MATCH_BNE = 0x00001063u,
  RV64I_MATCH_EBREAK = 0x00100073u,
  RV64I_MATCH_ECALL = 0x00000073u,
  RV64I_MATCH_FENCE = 0x0000000fu, // `fence.i` lives in Zifencei but is exercised by `rv64ui`.
  RV64I_MATCH_FENCE_I = 0x0000100fu,
  RV64I_MATCH_JAL = 0x0000006fu,
  RV64I_MATCH_JALR = 0x00000067u,
  RV64I_MATCH_LB = 0x00000003u,
  RV64I_MATCH_LBU = 0x00004003u,
  RV64I_MATCH_LD = 0x00003003u,
  RV64I_MATCH_LH = 0x00001003u,
  RV64I_MATCH_LHU = 0x00005003u,
  RV64I_MATCH_LUI = 0x00000037u,
  RV64I_MATCH_LW = 0x00002003u,
  RV64I_MATCH_LWU = 0x00006003u,
  RV64I_MATCH_OR = 0x00006033u,
  RV64I_MATCH_ORI = 0x00006013u,
  RV64I_MATCH_SB = 0x00000023u,
  RV64I_MATCH_SD = 0x00003023u,
  RV64I_MATCH_SH = 0x00001023u,
  RV64I_MATCH_SLL = 0x00001033u,
  RV64I_MATCH_SLLI = 0x00001013u,
  RV64I_MATCH_SLLIW = 0x0000101bu,
  RV64I_MATCH_SLLW = 0x0000103bu,
  RV64I_MATCH_SLT = 0x00002033u,
  RV64I_MATCH_SLTI = 0x00002013u,
  RV64I_MATCH_SLTIU = 0x00003013u,
  RV64I_MATCH_SLTU = 0x00003033u,
  RV64I_MATCH_SRA = 0x40005033u,
  RV64I_MATCH_SRAI = 0x40005013u,
  RV64I_MATCH_SRAIW = 0x4000501bu,
  RV64I_MATCH_SRAW = 0x4000503bu,
  RV64I_MATCH_SRL = 0x00005033u,
  RV64I_MATCH_SRLI = 0x00005013u,
  RV64I_MATCH_SRLIW = 0x0000501bu,
  RV64I_MATCH_SRLW = 0x0000503bu,
  RV64I_MATCH_SUB = 0x40000033u,
  RV64I_MATCH_SUBW = 0x4000003bu,
  RV64I_MATCH_SW = 0x00002023u,
  RV64I_MATCH_XOR = 0x00004033u,
  RV64I_MATCH_XORI = 0x00004013u,
};

/* RV64M extension — multiply/divide.  Same R-format as RV64I. */
enum {
  RV64M_MATCH_MUL = 0x02000033u,
  RV64M_MATCH_DIV = 0x02004033u,
  RV64M_MATCH_DIVU = 0x02005033u,
  RV64M_MATCH_REM = 0x02006033u,
  RV64M_MATCH_REMU = 0x02007033u,
  RV64M_MATCH_MULW = 0x0200003bu,
  RV64M_MATCH_DIVW = 0x0200403bu,
  RV64M_MATCH_DIVUW = 0x0200503bu,
  RV64M_MATCH_REMW = 0x0200603bu,
  RV64M_MATCH_REMUW = 0x0200703bu,
};

#define rv64m_mul(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64M_MATCH_MUL, rd, rs1, rs2, 0, 0)
#define rv64m_div(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64M_MATCH_DIV, rd, rs1, rs2, 0, 0)
#define rv64m_divu(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64M_MATCH_DIVU, rd, rs1, rs2, 0, 0)
#define rv64m_rem(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64M_MATCH_REM, rd, rs1, rs2, 0, 0)
#define rv64m_remu(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64M_MATCH_REMU, rd, rs1, rs2, 0, 0)
#define rv64m_mulw(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64M_MATCH_MULW, rd, rs1, rs2, 0, 0)
#define rv64m_divw(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64M_MATCH_DIVW, rd, rs1, rs2, 0, 0)
#define rv64m_divuw(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64M_MATCH_DIVUW, rd, rs1, rs2, 0, 0)
#define rv64m_remw(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64M_MATCH_REMW, rd, rs1, rs2, 0, 0)
#define rv64m_remuw(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64M_MATCH_REMUW, rd, rs1, rs2, 0, 0)

#define rv64i_add(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_ADD, rd, rs1, rs2, 0, 0)
#define rv64i_addi(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_ADDI, rd, rs1, imm, 0, 0)
#define rv64i_addiw(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_ADDIW, rd, rs1, imm, 0, 0)
#define rv64i_addw(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_ADDW, rd, rs1, rs2, 0, 0)
#define rv64i_and(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_AND, rd, rs1, rs2, 0, 0)
#define rv64i_andi(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_ANDI, rd, rs1, imm, 0, 0)
#define rv64i_auipc(rd, imm) \
  rv64i_emit(RV64I_FORMAT_U, RV64I_MATCH_AUIPC, rd, imm, 0, 0, 0)
#define rv64i_beq(rs1, rs2, imm) \
  rv64i_emit(RV64I_FORMAT_B, RV64I_MATCH_BEQ, rs1, rs2, imm, 0, 0)
#define rv64i_bge(rs1, rs2, imm) \
  rv64i_emit(RV64I_FORMAT_B, RV64I_MATCH_BGE, rs1, rs2, imm, 0, 0)
#define rv64i_bgeu(rs1, rs2, imm) \
  rv64i_emit(RV64I_FORMAT_B, RV64I_MATCH_BGEU, rs1, rs2, imm, 0, 0)
#define rv64i_blt(rs1, rs2, imm) \
  rv64i_emit(RV64I_FORMAT_B, RV64I_MATCH_BLT, rs1, rs2, imm, 0, 0)
#define rv64i_bltu(rs1, rs2, imm) \
  rv64i_emit(RV64I_FORMAT_B, RV64I_MATCH_BLTU, rs1, rs2, imm, 0, 0)
#define rv64i_bne(rs1, rs2, imm) \
  rv64i_emit(RV64I_FORMAT_B, RV64I_MATCH_BNE, rs1, rs2, imm, 0, 0)
#define rv64i_ebreak() \
  rv64i_emit(RV64I_FORMAT_FIXED, RV64I_MATCH_EBREAK, 0, 0, 0, 0, 0)
#define rv64i_ecall() \
  rv64i_emit(RV64I_FORMAT_FIXED, RV64I_MATCH_ECALL, 0, 0, 0, 0, 0)
#define rv64i_fence(fm, pred, succ, rs1, rd) \
  rv64i_emit(RV64I_FORMAT_FENCE, RV64I_MATCH_FENCE, fm, pred, succ, rs1, rd)
#define rv64i_fence_i() \
  rv64i_emit(RV64I_FORMAT_FIXED, RV64I_MATCH_FENCE_I, 0, 0, 0, 0, 0)
#define rv64i_jal(rd, imm) \
  rv64i_emit(RV64I_FORMAT_J, RV64I_MATCH_JAL, rd, imm, 0, 0, 0)
#define rv64i_jalr(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_JALR, rd, rs1, imm, 0, 0)
#define rv64i_lb(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_LB, rd, rs1, imm, 0, 0)
#define rv64i_lbu(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_LBU, rd, rs1, imm, 0, 0)
#define rv64i_ld(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_LD, rd, rs1, imm, 0, 0)
#define rv64i_lh(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_LH, rd, rs1, imm, 0, 0)
#define rv64i_lhu(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_LHU, rd, rs1, imm, 0, 0)
#define rv64i_lui(rd, imm) \
  rv64i_emit(RV64I_FORMAT_U, RV64I_MATCH_LUI, rd, imm, 0, 0, 0)
#define rv64i_lw(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_LW, rd, rs1, imm, 0, 0)
#define rv64i_lwu(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_LWU, rd, rs1, imm, 0, 0)
#define rv64i_or(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_OR, rd, rs1, rs2, 0, 0)
#define rv64i_ori(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_ORI, rd, rs1, imm, 0, 0)
#define rv64i_sb(rs1, rs2, imm) \
  rv64i_emit(RV64I_FORMAT_S, RV64I_MATCH_SB, rs1, rs2, imm, 0, 0)
#define rv64i_sd(rs1, rs2, imm) \
  rv64i_emit(RV64I_FORMAT_S, RV64I_MATCH_SD, rs1, rs2, imm, 0, 0)
#define rv64i_sh(rs1, rs2, imm) \
  rv64i_emit(RV64I_FORMAT_S, RV64I_MATCH_SH, rs1, rs2, imm, 0, 0)
#define rv64i_sll(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SLL, rd, rs1, rs2, 0, 0)
#define rv64i_slli(rd, rs1, shamt) \
  rv64i_emit(RV64I_FORMAT_I_SHAMT6, RV64I_MATCH_SLLI, rd, rs1, shamt, 0, 0)
#define rv64i_slliw(rd, rs1, shamt) \
  rv64i_emit(RV64I_FORMAT_I_SHAMT5, RV64I_MATCH_SLLIW, rd, rs1, shamt, 0, 0)
#define rv64i_sllw(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SLLW, rd, rs1, rs2, 0, 0)
#define rv64i_slt(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SLT, rd, rs1, rs2, 0, 0)
#define rv64i_slti(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_SLTI, rd, rs1, imm, 0, 0)
#define rv64i_sltiu(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_SLTIU, rd, rs1, imm, 0, 0)
#define rv64i_sltu(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SLTU, rd, rs1, rs2, 0, 0)
#define rv64i_sra(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SRA, rd, rs1, rs2, 0, 0)
#define rv64i_srai(rd, rs1, shamt) \
  rv64i_emit(RV64I_FORMAT_I_SHAMT6, RV64I_MATCH_SRAI, rd, rs1, shamt, 0, 0)
#define rv64i_sraiw(rd, rs1, shamt) \
  rv64i_emit(RV64I_FORMAT_I_SHAMT5, RV64I_MATCH_SRAIW, rd, rs1, shamt, 0, 0)
#define rv64i_sraw(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SRAW, rd, rs1, rs2, 0, 0)
#define rv64i_srl(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SRL, rd, rs1, rs2, 0, 0)
#define rv64i_srli(rd, rs1, shamt) \
  rv64i_emit(RV64I_FORMAT_I_SHAMT6, RV64I_MATCH_SRLI, rd, rs1, shamt, 0, 0)
#define rv64i_srliw(rd, rs1, shamt) \
  rv64i_emit(RV64I_FORMAT_I_SHAMT5, RV64I_MATCH_SRLIW, rd, rs1, shamt, 0, 0)
#define rv64i_srlw(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SRLW, rd, rs1, rs2, 0, 0)
#define rv64i_sub(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SUB, rd, rs1, rs2, 0, 0)
#define rv64i_subw(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SUBW, rd, rs1, rs2, 0, 0)
#define rv64i_sw(rs1, rs2, imm) \
  rv64i_emit(RV64I_FORMAT_S, RV64I_MATCH_SW, rs1, rs2, imm, 0, 0)
#define rv64i_xor(rd, rs1, rs2) \
  rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_XOR, rd, rs1, rs2, 0, 0)
#define rv64i_xori(rd, rs1, imm) \
  rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_XORI, rd, rs1, imm, 0, 0)

#endif /* BAREMETAL_HIGH_LEVEL_PROTOTYPE_RV64IM_API_H */
