#include "emitter.h"
#include "emitter_internal.h"

enum {
  DEFINE_MAX = 128,
  STATEMENT_MAX = 4096,
  STRING_TEXT_MAX = 160,
};

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
};

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
  RV64I_MATCH_FENCE = 0x0ff0000fu,
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

enum {
  RV64M_MATCH_MUL = 0x02000033u,
  RV64M_MATCH_MULH = 0x02001033u,
  RV64M_MATCH_MULHSU = 0x02002033u,
  RV64M_MATCH_MULHU = 0x02003033u,
  RV64M_MATCH_MULW = 0x0200003bu,
  RV64M_MATCH_DIV = 0x02004033u,
  RV64M_MATCH_DIVU = 0x02005033u,
  RV64M_MATCH_DIVW = 0x0200403bu,
  RV64M_MATCH_DIVUW = 0x0200503bu,
  RV64M_MATCH_REM = 0x02006033u,
  RV64M_MATCH_REMU = 0x02007033u,
  RV64M_MATCH_REMW = 0x0200603bu,
  RV64M_MATCH_REMUW = 0x0200703bu,
};

enum asm_token_kind { ASM_TOKEN_NONE, ASM_TOKEN_ATOM, ASM_TOKEN_STRING };

struct asm_token {
  uint8_t kind;
  char text[STRING_TEXT_MAX];
};

enum asm_statement_kind {
  ASM_STATEMENT_NONE,
  ASM_STATEMENT_EQU,
  ASM_STATEMENT_LABEL,
  ASM_STATEMENT_NOP,
  ASM_STATEMENT_BYTES,
  ASM_STATEMENT_DWORD,
  ASM_STATEMENT_WORD,
  ASM_STATEMENT_STRING,
  ASM_STATEMENT_ALIGN,
  ASM_STATEMENT_INSTR,
};

struct asm_statement {
  uint8_t kind;
  uint32_t line_number;
  struct asm_token name;
  struct asm_token operands[5];
  uint8_t operand_count;
};

struct asm_define {
  char name[TOKEN_TEXT_MAX];
  struct asm_token value[3];
  uint8_t value_count;
};

struct asm_program {
  struct asm_statement statements[STATEMENT_MAX];
  uint32_t statement_count;
  struct asm_define defines[DEFINE_MAX];
  uint32_t define_count;
};

static struct asm_program g_as0_program_storage;
static struct byte_buffer g_as0_buffer_storage;

/* ---- Utility ---- */

static uint32_t rv64i_emit(enum rv64i_format format, uint32_t match, int arg0,
                           int arg1, int arg2) {
  switch (format) {
    case RV64I_FORMAT_FIXED:
      return match;
    case RV64I_FORMAT_R:
      return match | ((((uint32_t)arg0) & 0x1fu) << 7) |
             ((((uint32_t)arg1) & 0x1fu) << 15) |
             ((((uint32_t)arg2) & 0x1fu) << 20);
    case RV64I_FORMAT_I:
      return match | ((((uint32_t)arg0) & 0x1fu) << 7) |
             ((((uint32_t)arg1) & 0x1fu) << 15) |
             ((((uint32_t)arg2) & 0xfffu) << 20);
    case RV64I_FORMAT_I_SHAMT6:
      return match | ((((uint32_t)arg0) & 0x1fu) << 7) |
             ((((uint32_t)arg1) & 0x1fu) << 15) |
             ((((uint32_t)arg2) & 0x3fu) << 20);
    case RV64I_FORMAT_I_SHAMT5:
      return match | ((((uint32_t)arg0) & 0x1fu) << 7) |
             ((((uint32_t)arg1) & 0x1fu) << 15) |
             ((((uint32_t)arg2) & 0x1fu) << 20);
    case RV64I_FORMAT_S:
      return match | (((((uint32_t)arg2) >> 5) & 0x7fu) << 25) |
             ((((uint32_t)arg0) & 0x1fu) << 15) |
             ((((uint32_t)arg1) & 0x1fu) << 20) |
             ((((uint32_t)arg2) & 0x1fu) << 7);
    case RV64I_FORMAT_B:
      return match | (((((uint32_t)arg2) >> 12) & 0x1u) << 31) |
             (((((uint32_t)arg2) >> 5) & 0x3fu) << 25) |
             ((((uint32_t)arg0) & 0x1fu) << 15) |
             ((((uint32_t)arg1) & 0x1fu) << 20) |
             (((((uint32_t)arg2) >> 1) & 0xfu) << 8) |
             (((((uint32_t)arg2) >> 11) & 0x1u) << 7);
    case RV64I_FORMAT_U:
      return match | ((((uint32_t)arg0) & 0x1fu) << 7) |
             ((((uint32_t)arg1) & 0xfffffu) << 12);
    case RV64I_FORMAT_J:
      return match | ((((uint32_t)arg0) & 0x1fu) << 7) |
             (((((uint32_t)arg1) >> 20) & 0x1u) << 31) |
             (((((uint32_t)arg1) >> 1) & 0x3ffu) << 21) |
             (((((uint32_t)arg1) >> 11) & 0x1u) << 20) |
             (((((uint32_t)arg1) >> 12) & 0xffu) << 12);
  }

  return 0;
}

static uint32_t rv64i_addi(int rd, int rs1, int imm) {
  return rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_ADDI, rd, rs1, imm);
}

static uint32_t rv64i_addiw(int rd, int rs1, int imm) {
  return rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_ADDIW, rd, rs1, imm);
}

static uint32_t rv64i_auipc(int rd, int imm) {
  return rv64i_emit(RV64I_FORMAT_U, RV64I_MATCH_AUIPC, rd, imm, 0);
}

static uint32_t rv64i_jalr(int rd, int rs1, int imm) {
  return rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_JALR, rd, rs1, imm);
}

static uint32_t rv64i_lui(int rd, int imm) {
  return rv64i_emit(RV64I_FORMAT_U, RV64I_MATCH_LUI, rd, imm, 0);
}

static int emit_byte(struct byte_buffer *buffer, uint8_t byte) {
  if (buffer->byte_count >= OUTPUT_MAX_BYTES) return 0;
  buffer->bytes[buffer->byte_count++] = byte;
  return 1;
}

static int emit_word_raw(struct byte_buffer *buffer, uint32_t word) {
  return emit_byte(buffer, (uint8_t)(word & 0xffu)) &&
         emit_byte(buffer, (uint8_t)((word >> 8) & 0xffu)) &&
         emit_byte(buffer, (uint8_t)((word >> 16) & 0xffu)) &&
         emit_byte(buffer, (uint8_t)((word >> 24) & 0xffu));
}

static int emit_dword_raw(struct byte_buffer *buffer, uint64_t word) {
  return emit_word_raw(buffer, (uint32_t)(word & 0xffffffffu)) &&
         emit_word_raw(buffer, (uint32_t)(word >> 32));
}

static int flush_buffer_to_sink(const struct byte_buffer *buffer,
                                struct code_sink *sink, const char *name,
                                const struct compile_diagnostics *diag) {
  sink->begin_program(sink, name);
  for (uint32_t i = 0; i < buffer->byte_count; ++i) {
    sink->write_byte(sink, buffer->bytes[i]);
  }
  sink->end_program(sink, name, diag);
  return 1;
}

static int strings_equal(const char *a, const char *b) {
  while (*a && *b) {
    if (*a != *b) return 0;
    a++;
    b++;
  }
  return *a == *b;
}

static void hi_lo_split(int32_t offset, uint32_t *hi_out, uint32_t *lo_out);

static void copy_text(char *dst, uint32_t sz, const char *src) {
  uint32_t i = 0;
  while (i + 1u < sz && src[i]) {
    dst[i] = src[i];
    i++;
  }
  dst[i] = '\0';
}

static int add_label(struct byte_buffer *buf, const char *name, int32_t off) {
  for (uint32_t i = 0; i < buf->label_count; i++)
    if (strings_equal(buf->labels[i].name, name)) return 0;
  if (buf->label_count >= LABEL_MAX) return 0;
  copy_text(buf->labels[buf->label_count].name, TOKEN_TEXT_MAX, name);
  buf->labels[buf->label_count].offset = off;
  buf->label_count++;
  return 1;
}

static int lookup_label(const struct byte_buffer *buf, const char *name,
                        int32_t *out) {
  for (uint32_t i = 0; i < buf->label_count; i++) {
    if (strings_equal(buf->labels[i].name, name)) {
      *out = buf->labels[i].offset;
      return 1;
    }
  }
  return 0;
}

static int parse_number(const char *text, int32_t *out) {
  int sign = 1;
  int32_t val = 0;
  uint32_t i = 0;
  int base = 10;

  if (text[0] == '-') { sign = -1; i = 1; }
  if (text[i] == '0' && (text[i + 1] == 'x' || text[i + 1] == 'X')) {
    base = 16;
    i += 2;
  }
  if (text[i] == '\0') return 0;

  while (text[i]) {
    int d = -1;
    char c = text[i];
    if (c >= '0' && c <= '9') d = c - '0';
    else if (base == 16 && c >= 'a' && c <= 'f') d = 10 + c - 'a';
    else if (base == 16 && c >= 'A' && c <= 'F') d = 10 + c - 'A';
    if (d < 0 || d >= base) return 0;
    val = (base == 16) ? (val << 4) + d : (val << 3) + (val << 1) + d;
    i++;
  }
  *out = sign < 0 ? -val : val;
  return 1;
}

static void token_copy(struct asm_token *dst, const struct asm_token *src) {
  dst->kind = src->kind;
  copy_text(dst->text, STRING_TEXT_MAX, src->text);
}

static const struct asm_define *lookup_define(const struct asm_program *program,
                                              const char *name) {
  for (uint32_t i = 0; i < program->define_count; ++i) {
    if (strings_equal(program->defines[i].name, name)) return &program->defines[i];
  }
  return 0;
}

static int resolve_define_value(const struct asm_program *program,
                                const char *name, int32_t *out, uint32_t depth) {
  const struct asm_define *def;
  int32_t left;
  int32_t right;

  if (depth >= DEFINE_MAX) return 0;
  def = lookup_define(program, name);
  if (!def || def->value_count == 0u || def->value_count > 3u) return 0;

  if (def->value_count == 1u) {
    if (parse_number(def->value[0].text, out)) return 1;
    return resolve_define_value(program, def->value[0].text, out, depth + 1u);
  }

  if (!resolve_define_value(program, def->value[0].text, &left, depth + 1u) &&
      !parse_number(def->value[0].text, &left))
    return 0;
  if (!resolve_define_value(program, def->value[2].text, &right, depth + 1u) &&
      !parse_number(def->value[2].text, &right))
    return 0;

  if (strings_equal(def->value[1].text, "+")) {
    *out = left + right;
    return 1;
  }
  if (strings_equal(def->value[1].text, "-")) {
    *out = left - right;
    return 1;
  }
  return 0;
}

static int parse_value(const struct asm_program *program, const char *text,
                       int32_t *out) {
  if (text[0] == '-') {
    if (!parse_value(program, text + 1, out)) return 0;
    *out = -*out;
    return 1;
  }
  if (text[0] == '\'') {
    if (text[1] == '\\') {
      if (text[2] == '\0' || text[3] != '\'' || text[4] != '\0') return 0;
      switch (text[2]) {
        case 't': *out = '\t'; return 1;
        case 'n': *out = '\n'; return 1;
        case '0': *out = '\0'; return 1;
        case '\\': *out = '\\'; return 1;
        case '\'': *out = '\''; return 1;
        case '"': *out = '"'; return 1;
        default: return 0;
      }
    }
    if (text[1] == '\0' || text[2] != '\'' || text[3] != '\0') return 0;
    *out = (uint8_t)text[1];
    return 1;
  }
  if (parse_number(text, out)) return 1;
  return resolve_define_value(program, text, out, 0u);
}

static int eval_token_expr(const struct asm_program *program,
                           const struct asm_token *tokens, uint32_t count,
                           int32_t *out) {
  int32_t left;
  int32_t right;

  if (count == 1u) return parse_value(program, tokens[0].text, out);
  if (count != 3u) return 0;
  if (!parse_value(program, tokens[0].text, &left) ||
      !parse_value(program, tokens[2].text, &right))
    return 0;
  if (strings_equal(tokens[1].text, "+")) {
    *out = left + right;
    return 1;
  }
  if (strings_equal(tokens[1].text, "-")) {
    *out = left - right;
    return 1;
  }
  return 0;
}

/* ---- Register parser ---- */

static int parse_register(const char *text, int *out) {
  if (text[0] == 'x') {
    int32_t n;
    if (parse_number(text + 1, &n) && n >= 0 && n <= 31) {
      *out = (int)n;
      return 1;
    }
    return 0;
  }
  if (strings_equal(text, "zero")) { *out = 0; return 1; }
  if (strings_equal(text, "ra"))   { *out = 1; return 1; }
  if (strings_equal(text, "sp"))   { *out = 2; return 1; }
  if (strings_equal(text, "gp"))   { *out = 3; return 1; }
  if (strings_equal(text, "tp"))   { *out = 4; return 1; }
  if (strings_equal(text, "fp"))   { *out = 8; return 1; }
  if (text[0] == 't' && text[2] == '\0') {
    if (text[1] >= '0' && text[1] <= '2') { *out = 5 + text[1] - '0'; return 1; }
    if (text[1] >= '3' && text[1] <= '6') { *out = 25 + text[1] - '0'; return 1; }
  }
  if (text[0] == 'a' && text[1] >= '0' && text[1] <= '7' && text[2] == '\0') {
    *out = 10 + text[1] - '0';
    return 1;
  }
  if (text[0] == 's') {
    int32_t n;
    if (parse_number(text + 1, &n)) {
      if (n >= 0 && n <= 1) { *out = 8 + (int)n; return 1; }
      if (n >= 2 && n <= 11) { *out = 16 + (int)n; return 1; }
    }
  }
  return 0;
}

/* ---- Instruction table ---- */

enum insn_pattern {
  PAT_R, PAT_I, PAT_LOAD, PAT_STORE, PAT_B, PAT_U, PAT_J,
  PAT_SHAMT6, PAT_SHAMT5, PAT_FIXED,
  PAT_LI, PAT_LA, PAT_MV, PAT_RET, PAT_NOP, PAT_CALL, PAT_TAIL,
  PAT_JUMP, PAT_JR, PAT_BEQZ, PAT_BNEZ, PAT_BLEZ, PAT_BGEZ, PAT_BLTZ, PAT_BGTZ,
  PAT_BGT, PAT_BLE, PAT_BGTU, PAT_BLEU,
  PAT_NEG, PAT_NEGW, PAT_NOT, PAT_SEQZ, PAT_SNEZ, PAT_SGTZ, PAT_SLTZ,
};

struct insn_entry {
  char mnemonic[8];
  uint8_t pattern;
  uint8_t format;
  uint32_t match;
};

static const struct insn_entry g_insn_table[] = {
  {"add",    PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_ADD},
  {"addw",   PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_ADDW},
  {"and",    PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_AND},
  {"div",    PAT_R,      RV64I_FORMAT_R,        RV64M_MATCH_DIV},
  {"divu",   PAT_R,      RV64I_FORMAT_R,        RV64M_MATCH_DIVU},
  {"divuw",  PAT_R,      RV64I_FORMAT_R,        RV64M_MATCH_DIVUW},
  {"divw",   PAT_R,      RV64I_FORMAT_R,        RV64M_MATCH_DIVW},
  {"mul",    PAT_R,      RV64I_FORMAT_R,        RV64M_MATCH_MUL},
  {"mulh",   PAT_R,      RV64I_FORMAT_R,        RV64M_MATCH_MULH},
  {"mulhsu", PAT_R,      RV64I_FORMAT_R,        RV64M_MATCH_MULHSU},
  {"mulhu",  PAT_R,      RV64I_FORMAT_R,        RV64M_MATCH_MULHU},
  {"mulw",   PAT_R,      RV64I_FORMAT_R,        RV64M_MATCH_MULW},
  {"or",     PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_OR},
  {"rem",    PAT_R,      RV64I_FORMAT_R,        RV64M_MATCH_REM},
  {"remu",   PAT_R,      RV64I_FORMAT_R,        RV64M_MATCH_REMU},
  {"remuw",  PAT_R,      RV64I_FORMAT_R,        RV64M_MATCH_REMUW},
  {"remw",   PAT_R,      RV64I_FORMAT_R,        RV64M_MATCH_REMW},
  {"sll",    PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_SLL},
  {"sllw",   PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_SLLW},
  {"slt",    PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_SLT},
  {"sltu",   PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_SLTU},
  {"sra",    PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_SRA},
  {"sraw",   PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_SRAW},
  {"srl",    PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_SRL},
  {"srlw",   PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_SRLW},
  {"sub",    PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_SUB},
  {"subw",   PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_SUBW},
  {"xor",    PAT_R,      RV64I_FORMAT_R,        RV64I_MATCH_XOR},
  {"addi",   PAT_I,      RV64I_FORMAT_I,        RV64I_MATCH_ADDI},
  {"addiw",  PAT_I,      RV64I_FORMAT_I,        RV64I_MATCH_ADDIW},
  {"andi",   PAT_I,      RV64I_FORMAT_I,        RV64I_MATCH_ANDI},
  {"jalr",   PAT_I,      RV64I_FORMAT_I,        RV64I_MATCH_JALR},
  {"ori",    PAT_I,      RV64I_FORMAT_I,        RV64I_MATCH_ORI},
  {"slti",   PAT_I,      RV64I_FORMAT_I,        RV64I_MATCH_SLTI},
  {"sltiu",  PAT_I,      RV64I_FORMAT_I,        RV64I_MATCH_SLTIU},
  {"xori",   PAT_I,      RV64I_FORMAT_I,        RV64I_MATCH_XORI},
  {"lb",     PAT_LOAD,   RV64I_FORMAT_I,        RV64I_MATCH_LB},
  {"lbu",    PAT_LOAD,   RV64I_FORMAT_I,        RV64I_MATCH_LBU},
  {"ld",     PAT_LOAD,   RV64I_FORMAT_I,        RV64I_MATCH_LD},
  {"lh",     PAT_LOAD,   RV64I_FORMAT_I,        RV64I_MATCH_LH},
  {"lhu",    PAT_LOAD,   RV64I_FORMAT_I,        RV64I_MATCH_LHU},
  {"lw",     PAT_LOAD,   RV64I_FORMAT_I,        RV64I_MATCH_LW},
  {"lwu",    PAT_LOAD,   RV64I_FORMAT_I,        RV64I_MATCH_LWU},
  {"sb",     PAT_STORE,  RV64I_FORMAT_S,        RV64I_MATCH_SB},
  {"sd",     PAT_STORE,  RV64I_FORMAT_S,        RV64I_MATCH_SD},
  {"sh",     PAT_STORE,  RV64I_FORMAT_S,        RV64I_MATCH_SH},
  {"sw",     PAT_STORE,  RV64I_FORMAT_S,        RV64I_MATCH_SW},
  {"beq",    PAT_B,      RV64I_FORMAT_B,        RV64I_MATCH_BEQ},
  {"bge",    PAT_B,      RV64I_FORMAT_B,        RV64I_MATCH_BGE},
  {"bgeu",   PAT_B,      RV64I_FORMAT_B,        RV64I_MATCH_BGEU},
  {"blt",    PAT_B,      RV64I_FORMAT_B,        RV64I_MATCH_BLT},
  {"bltu",   PAT_B,      RV64I_FORMAT_B,        RV64I_MATCH_BLTU},
  {"bne",    PAT_B,      RV64I_FORMAT_B,        RV64I_MATCH_BNE},
  {"auipc",  PAT_U,      RV64I_FORMAT_U,        RV64I_MATCH_AUIPC},
  {"lui",    PAT_U,      RV64I_FORMAT_U,        RV64I_MATCH_LUI},
  {"jal",    PAT_J,      RV64I_FORMAT_J,        RV64I_MATCH_JAL},
  {"slli",   PAT_SHAMT6, RV64I_FORMAT_I_SHAMT6, RV64I_MATCH_SLLI},
  {"srai",   PAT_SHAMT6, RV64I_FORMAT_I_SHAMT6, RV64I_MATCH_SRAI},
  {"srli",   PAT_SHAMT6, RV64I_FORMAT_I_SHAMT6, RV64I_MATCH_SRLI},
  {"slliw",  PAT_SHAMT5, RV64I_FORMAT_I_SHAMT5, RV64I_MATCH_SLLIW},
  {"sraiw",  PAT_SHAMT5, RV64I_FORMAT_I_SHAMT5, RV64I_MATCH_SRAIW},
  {"srliw",  PAT_SHAMT5, RV64I_FORMAT_I_SHAMT5, RV64I_MATCH_SRLIW},
  {"fence",  PAT_FIXED,  RV64I_FORMAT_FIXED,    RV64I_MATCH_FENCE},
  {"fence.i",PAT_FIXED,  RV64I_FORMAT_FIXED,    RV64I_MATCH_FENCE_I},
  {"ebreak", PAT_FIXED,  RV64I_FORMAT_FIXED,    RV64I_MATCH_EBREAK},
  {"ecall",  PAT_FIXED,  RV64I_FORMAT_FIXED,    RV64I_MATCH_ECALL},
  {"li",     PAT_LI,     0, 0},
  {"la",     PAT_LA,     0, 0},
  {"mv",     PAT_MV,     0, 0},
  {"ret",    PAT_RET,    0, 0},
  {"nop",    PAT_NOP,    0, 0},
  {"call",   PAT_CALL,   0, 0},
  {"tail",   PAT_TAIL,   0, 0},
  {"j",      PAT_JUMP,   0, 0},
  {"jr",     PAT_JR,     0, 0},
  {"beqz",   PAT_BEQZ,   0, 0},
  {"bnez",   PAT_BNEZ,   0, 0},
  {"blez",   PAT_BLEZ,   0, 0},
  {"bgez",   PAT_BGEZ,   0, 0},
  {"bltz",   PAT_BLTZ,   0, 0},
  {"bgtz",   PAT_BGTZ,   0, 0},
  {"bgt",    PAT_BGT,    0, 0},
  {"ble",    PAT_BLE,    0, 0},
  {"bgtu",   PAT_BGTU,   0, 0},
  {"bleu",   PAT_BLEU,   0, 0},
  {"neg",    PAT_NEG,    0, 0},
  {"negw",   PAT_NEGW,   0, 0},
  {"not",    PAT_NOT,    0, 0},
  {"seqz",   PAT_SEQZ,   0, 0},
  {"snez",   PAT_SNEZ,   0, 0},
  {"sgtz",   PAT_SGTZ,   0, 0},
  {"sltz",   PAT_SLTZ,   0, 0},
};

#define INSN_TABLE_SIZE (sizeof(g_insn_table) / sizeof(g_insn_table[0]))

static const struct insn_entry *lookup_insn(const char *mnemonic) {
  for (uint32_t i = 0; i < INSN_TABLE_SIZE; i++) {
    if (strings_equal(g_insn_table[i].mnemonic, mnemonic))
      return &g_insn_table[i];
  }
  return 0;
}

/* ---- Tokenizer ---- */

static int tokenize_line(const char *line, struct asm_token *tokens,
                         uint32_t *token_count_out) {
  uint32_t count = 0;
  uint32_t i = 0;

  while (line[i]) {
    while (line[i] == ' ' || line[i] == '\t' || line[i] == ',' ||
           line[i] == '(' || line[i] == ')') {
      i++;
    }
    if (!line[i] || line[i] == '#' || line[i] == ';') break;
    if (count >= 6) return 0;

    if (line[i] == '\'') {
      uint32_t out = 0;
      tokens[count].kind = ASM_TOKEN_ATOM;
      if (out + 1u >= STRING_TEXT_MAX) return 0;
      tokens[count].text[out++] = line[i++];
      if (!line[i]) return 0;
      for (;;) {
        if (out + 1u >= STRING_TEXT_MAX) return 0;
        tokens[count].text[out++] = line[i++];
        if (tokens[count].text[out - 1u] == '\\' && line[i]) {
          if (out + 1u >= STRING_TEXT_MAX) return 0;
          tokens[count].text[out++] = line[i++];
        } else if (tokens[count].text[out - 1u] == '\'') {
          break;
        } else if (!line[i]) {
          return 0;
        }
      }
      tokens[count].text[out] = '\0';
      count++;
      continue;
    }

    if (line[i] == '"') {
      uint32_t out = 0;
      i++;
      tokens[count].kind = ASM_TOKEN_STRING;
      while (line[i] && line[i] != '"') {
        if (line[i] == '\\' && line[i + 1]) {
          i++;
          switch (line[i]) {
            case 'n':  tokens[count].text[out++] = '\n'; break;
            case 't':  tokens[count].text[out++] = '\t'; break;
            case '"':  tokens[count].text[out++] = '"';  break;
            case '\\': tokens[count].text[out++] = '\\'; break;
            default: return 0;
          }
        } else {
          if (out + 1u >= STRING_TEXT_MAX) return 0;
          tokens[count].text[out++] = line[i];
        }
        i++;
      }
      if (line[i] != '"') return 0;
      tokens[count].text[out] = '\0';
      count++;
      i++;
      continue;
    }

    {
      uint32_t out = 0;
      tokens[count].kind = ASM_TOKEN_ATOM;
      while (line[i] && line[i] != ' ' && line[i] != '\t' &&
             line[i] != '#' && line[i] != ';' && line[i] != ',' &&
             line[i] != '(' && line[i] != ')') {
        if (out + 1u >= STRING_TEXT_MAX) return 0;
        tokens[count].text[out++] = line[i++];
      }
      tokens[count].text[out] = '\0';
      count++;
    }
  }

  *token_count_out = count;
  return 1;
}

/* ---- Parser ---- */

static int parse_text_source(const char *source, struct asm_program *program) {
  uint32_t line_number = 1;
  uint32_t pos = 0;

  program->statement_count = 0;
  program->define_count = 0;

  while (source[pos]) {
    char line[256];
    uint32_t line_len = 0;
    struct asm_token tokens[6];
    uint32_t token_count = 0;

    while (source[pos] && source[pos] != '\n') {
      if (line_len + 1u >= sizeof(line)) return 0;
      line[line_len++] = source[pos++];
    }
    line[line_len] = '\0';
    if (source[pos] == '\n') pos++;

    if (!tokenize_line(line, tokens, &token_count)) return 0;
    if (token_count == 0) { line_number++; continue; }
    if (program->statement_count >= STATEMENT_MAX) return 0;

    {
      struct asm_statement *s = &program->statements[program->statement_count];
      s->kind = ASM_STATEMENT_NONE;
      s->line_number = line_number;
      s->operand_count = 0;
      s->name.kind = ASM_TOKEN_NONE;
      s->name.text[0] = '\0';

      /* Label: token ending with ':' */
      if (tokens[0].kind == ASM_TOKEN_ATOM) {
        uint32_t len = 0;
        while (tokens[0].text[len]) len++;
        if (len > 0u && tokens[0].text[len - 1u] == ':') {
          s->kind = ASM_STATEMENT_LABEL;
          copy_text(s->name.text, STRING_TEXT_MAX, tokens[0].text);
          s->name.text[len - 1u] = '\0';
          s->name.kind = ASM_TOKEN_ATOM;
          program->statement_count++;
          line_number++;
          continue;
        }
      }

      /* Directives starting with '.' */
      if (tokens[0].text[0] == '.') {
        if (strings_equal(tokens[0].text, ".equ")) {
          s->kind = ASM_STATEMENT_EQU;
        } else if (strings_equal(tokens[0].text, ".text") ||
                   strings_equal(tokens[0].text, ".global")) {
          s->kind = ASM_STATEMENT_NOP;
        } else if (strings_equal(tokens[0].text, ".byte")) {
          s->kind = ASM_STATEMENT_BYTES;
        } else if (strings_equal(tokens[0].text, ".dword")) {
          s->kind = ASM_STATEMENT_DWORD;
        } else if (strings_equal(tokens[0].text, ".word")) {
          s->kind = ASM_STATEMENT_WORD;
        } else if (strings_equal(tokens[0].text, ".string")) {
          s->kind = ASM_STATEMENT_STRING;
        } else if (strings_equal(tokens[0].text, ".align")) {
          s->kind = ASM_STATEMENT_ALIGN;
        } else {
          return 0;
        }
      } else {
        /* Instruction mnemonic */
        s->kind = ASM_STATEMENT_INSTR;
      }

      s->name.kind = tokens[0].kind;
      copy_text(s->name.text, STRING_TEXT_MAX, tokens[0].text);

      for (uint32_t j = 1; j < token_count && s->operand_count < 5; j++) {
        token_copy(&s->operands[s->operand_count], &tokens[j]);
        s->operand_count++;
      }
      program->statement_count++;
    }
    line_number++;
  }
  return 1;
}

/* ---- Define handling ---- */

static int collect_defines(struct asm_program *program) {
  for (uint32_t i = 0; i < program->statement_count; i++) {
    struct asm_statement *s = &program->statements[i];
    if (s->kind != ASM_STATEMENT_EQU) continue;
    if ((s->operand_count != 2u && s->operand_count != 4u) ||
        program->define_count >= DEFINE_MAX)
      return 0;
    copy_text(program->defines[program->define_count].name, TOKEN_TEXT_MAX,
              s->operands[0].text);
    if (s->operand_count == 2u) {
      token_copy(&program->defines[program->define_count].value[0], &s->operands[1]);
      program->defines[program->define_count].value_count = 1;
    } else {
      token_copy(&program->defines[program->define_count].value[0], &s->operands[1]);
      token_copy(&program->defines[program->define_count].value[1], &s->operands[2]);
      token_copy(&program->defines[program->define_count].value[2], &s->operands[3]);
      program->defines[program->define_count].value_count = 3;
    }
    program->define_count++;
  }
  return 1;
}

/* ---- First pass ---- */

static int insn_size(const struct asm_program *program,
                     const struct asm_statement *s, uint32_t *size_out) {
  const struct insn_entry *e = lookup_insn(s->name.text);
  if (!e) return 0;
  switch (e->pattern) {
    case PAT_LA:
    case PAT_CALL:
    case PAT_TAIL:
      *size_out = 8;
      return 1;
    case PAT_LI: {
      int32_t imm;
      uint32_t hi, lo;
      if (s->operand_count != 2u && s->operand_count != 4u) return 0;
      if (!eval_token_expr(program, &s->operands[1], s->operand_count - 1u,
                           &imm))
        return 0;
      if (imm >= -2048 && imm <= 2047) {
        *size_out = 4;
        return 1;
      }
      hi_lo_split(imm, &hi, &lo);
      *size_out = (lo == 0u) ? 4 : 8;
      return 1;
    }
    case PAT_JUMP:
    case PAT_JR:
    case PAT_BEQZ:
    case PAT_BNEZ:
    case PAT_BLEZ:
    case PAT_BGEZ:
    case PAT_BLTZ:
    case PAT_BGTZ:
    case PAT_BGT:
    case PAT_BLE:
    case PAT_BGTU:
    case PAT_BLEU:
    case PAT_NEG:
    case PAT_NEGW:
    case PAT_NOT:
    case PAT_SEQZ:
    case PAT_SNEZ:
    case PAT_SGTZ:
    case PAT_SLTZ:
      *size_out = 4;
      return 1;
    default:
      *size_out = 4;
      return 1;
  }
}

static int statement_size(const struct asm_program *program,
                          const struct asm_statement *s, uint32_t *size_out) {
  switch (s->kind) {
    case ASM_STATEMENT_EQU:
    case ASM_STATEMENT_LABEL:
    case ASM_STATEMENT_NOP:
      *size_out = 0;
      return 1;
    case ASM_STATEMENT_BYTES:
      *size_out = s->operand_count;
      return 1;
    case ASM_STATEMENT_DWORD:
      *size_out = 8;
      return 1;
    case ASM_STATEMENT_WORD:
      *size_out = 4;
      return 1;
    case ASM_STATEMENT_STRING: {
      uint32_t len = 0;
      if (s->operand_count != 1 || s->operands[0].kind != ASM_TOKEN_STRING)
        return 0;
      while (s->operands[0].text[len]) len++;
      *size_out = len + 1u;
      return 1;
    }
    case ASM_STATEMENT_ALIGN:
      *size_out = 0;
      return 1;
    case ASM_STATEMENT_INSTR:
      return insn_size(program, s, size_out);
    default:
      return 0;
  }
}

static int align_padding(uint32_t offset, uint32_t alignment, uint32_t *out) {
  uint32_t rem = offset & (alignment - 1u);
  *out = rem ? alignment - rem : 0;
  return 1;
}

static int first_pass_text(struct asm_program *program, struct byte_buffer *buf) {
  uint32_t offset = 0;
  buf->label_count = 0;

  for (uint32_t i = 0; i < program->statement_count; i++) {
    struct asm_statement *s = &program->statements[i];
    uint32_t size;

    if (s->kind == ASM_STATEMENT_LABEL) {
      if (!add_label(buf, s->name.text, (int32_t)offset)) return 0;
      continue;
    }
    if (!statement_size(program, s, &size)) return 0;
    if (s->kind == ASM_STATEMENT_ALIGN) {
      uint32_t padding;
      if (!align_padding(offset, 4u, &padding)) return 0;
      offset += padding;
    } else {
      offset += size;
    }
  }
  return 1;
}

/* ---- Second pass helpers ---- */

static int resolve_offset(const struct asm_program *program,
                          const struct byte_buffer *buf, const char *text,
                          uint32_t current_pos, int32_t *out) {
  int32_t imm;
  if (parse_value(program, text, &imm)) {
    *out = imm;
    return 1;
  }
  int32_t label_off;
  if (lookup_label(buf, text, &label_off)) {
    *out = label_off - (int32_t)current_pos;
    return 1;
  }
  return 0;
}

static void hi_lo_split(int32_t offset, uint32_t *hi_out, uint32_t *lo_out) {
  uint32_t u = (uint32_t)offset;
  uint32_t lo = u & 0xFFFu;
  uint32_t hi = u & 0xFFFFF000u;
  if (lo >= 0x800u) hi += 0x1000u;
  *hi_out = hi;
  *lo_out = lo;
}

/* ---- Second pass ---- */

static int emit_instr(const struct asm_program *program,
                      const struct asm_statement *s, struct byte_buffer *buf) {
  const struct insn_entry *e = lookup_insn(s->name.text);
  if (!e) return 0;

  switch (e->pattern) {
    case PAT_R: {
      int rd, rs1, rs2;
      if (s->operand_count != 3 ||
          !parse_register(s->operands[0].text, &rd) ||
          !parse_register(s->operands[1].text, &rs1) ||
          !parse_register(s->operands[2].text, &rs2))
        return 0;
      return emit_word_raw(buf, rv64i_emit(e->format, e->match, rd, rs1, rs2));
    }
    case PAT_I:
    case PAT_SHAMT6:
    case PAT_SHAMT5: {
      int rd, rs1;
      int32_t imm;
      if (e->match == RV64I_MATCH_JALR && s->operand_count == 1u) {
        if (!parse_register(s->operands[0].text, &rs1)) return 0;
        return emit_word_raw(buf, rv64i_emit(e->format, e->match, 1, rs1, 0));
      }
      if (s->operand_count != 3 ||
          !parse_register(s->operands[0].text, &rd) ||
          !parse_register(s->operands[1].text, &rs1) ||
          !parse_value(program, s->operands[2].text, &imm))
        return 0;
      return emit_word_raw(buf, rv64i_emit(e->format, e->match, rd, rs1, imm));
    }
    case PAT_LOAD: {
      int rd, rs1;
      int32_t imm;
      if (s->operand_count != 3 ||
          !parse_register(s->operands[0].text, &rd) ||
          !parse_value(program, s->operands[1].text, &imm) ||
          !parse_register(s->operands[2].text, &rs1))
        return 0;
      return emit_word_raw(buf, rv64i_emit(e->format, e->match, rd, rs1, imm));
    }
    case PAT_STORE: {
      int rs2, rs1;
      int32_t imm;
      if (s->operand_count != 3 ||
          !parse_register(s->operands[0].text, &rs2) ||
          !parse_value(program, s->operands[1].text, &imm) ||
          !parse_register(s->operands[2].text, &rs1))
        return 0;
      return emit_word_raw(buf, rv64i_emit(e->format, e->match, rs1, rs2, imm));
    }
    case PAT_B: {
      int rs1, rs2;
      int32_t imm;
      if (s->operand_count != 3 ||
          !parse_register(s->operands[0].text, &rs1) ||
          !parse_register(s->operands[1].text, &rs2) ||
          !resolve_offset(program, buf, s->operands[2].text, buf->byte_count,
                          &imm))
        return 0;
      return emit_word_raw(buf, rv64i_emit(e->format, e->match, rs1, rs2, imm));
    }
    case PAT_U: {
      int rd;
      int32_t imm;
      if (s->operand_count != 2 ||
          !parse_register(s->operands[0].text, &rd) ||
          !parse_value(program, s->operands[1].text, &imm))
        return 0;
      return emit_word_raw(buf, rv64i_emit(e->format, e->match, rd, imm, 0));
    }
    case PAT_J: {
      int rd;
      int32_t imm;
      if (s->operand_count != 2 ||
          !parse_register(s->operands[0].text, &rd) ||
          !resolve_offset(program, buf, s->operands[1].text, buf->byte_count,
                          &imm))
        return 0;
      return emit_word_raw(buf, rv64i_emit(e->format, e->match, rd, imm, 0));
    }
    case PAT_FIXED: {
      if (s->operand_count != 0) return 0;
      return emit_word_raw(buf, rv64i_emit(e->format, e->match, 0, 0, 0));
    }
    case PAT_LI: {
      int rd;
      int32_t imm;
      if ((s->operand_count != 2u && s->operand_count != 4u) ||
          !parse_register(s->operands[0].text, &rd) ||
          !eval_token_expr(program, &s->operands[1], s->operand_count - 1u,
                           &imm))
        return 0;
      if (imm >= -2048 && imm <= 2047) {
        return emit_word_raw(buf, rv64i_addi(rd, 0, imm));
      } else {
        uint32_t hi, lo;
        hi_lo_split(imm, &hi, &lo);
        if (!emit_word_raw(buf, rv64i_lui(rd, hi >> 12))) return 0;
        if (lo == 0u) return 1;
        return emit_word_raw(buf, rv64i_addiw(rd, rd, (int32_t)lo));
      }
    }
    case PAT_LA: {
      int rd;
      int32_t label_off;
      if (s->operand_count != 2 ||
          !parse_register(s->operands[0].text, &rd) ||
          !lookup_label(buf, s->operands[1].text, &label_off))
        return 0;
      int32_t offset = label_off - (int32_t)buf->byte_count;
      uint32_t hi, lo;
      hi_lo_split(offset, &hi, &lo);
      return emit_word_raw(buf, rv64i_auipc(rd, hi >> 12)) &&
             emit_word_raw(buf, rv64i_addi(rd, rd, (int32_t)lo));
    }
    case PAT_MV: {
      int rd, rs;
      if (s->operand_count != 2 ||
          !parse_register(s->operands[0].text, &rd) ||
          !parse_register(s->operands[1].text, &rs))
        return 0;
      return emit_word_raw(buf, rv64i_addi(rd, rs, 0));
    }
    case PAT_RET:
      if (s->operand_count != 0) return 0;
      return emit_word_raw(buf, rv64i_jalr(0, 1, 0));
    case PAT_NOP:
      if (s->operand_count != 0) return 0;
      return emit_word_raw(buf, rv64i_addi(0, 0, 0));
    case PAT_CALL: {
      int32_t label_off;
      if (s->operand_count != 1 ||
          !lookup_label(buf, s->operands[0].text, &label_off))
        return 0;
      int32_t offset = label_off - (int32_t)buf->byte_count;
      uint32_t hi, lo;
      hi_lo_split(offset, &hi, &lo);
      return emit_word_raw(buf, rv64i_auipc(1, hi >> 12)) &&
             emit_word_raw(buf, rv64i_jalr(1, 1, (int32_t)lo));
    }
    case PAT_TAIL: {
      int32_t label_off;
      if (s->operand_count != 1 ||
          !lookup_label(buf, s->operands[0].text, &label_off))
        return 0;
      int32_t offset = label_off - (int32_t)buf->byte_count;
      uint32_t hi, lo;
      hi_lo_split(offset, &hi, &lo);
      return emit_word_raw(buf, rv64i_auipc(6, hi >> 12)) &&
             emit_word_raw(buf, rv64i_jalr(0, 6, (int32_t)lo));
    }
    case PAT_JUMP: {
      int32_t imm;
      if (s->operand_count != 1 ||
          !resolve_offset(program, buf, s->operands[0].text, buf->byte_count,
                          &imm))
        return 0;
      return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_J, RV64I_MATCH_JAL, 0, imm, 0));
    }
    case PAT_JR: {
      int rs;
      if (s->operand_count != 1 ||
          !parse_register(s->operands[0].text, &rs))
        return 0;
      return emit_word_raw(buf, rv64i_jalr(0, rs, 0));
    }
    case PAT_BEQZ:
    case PAT_BNEZ:
    case PAT_BLEZ:
    case PAT_BGEZ:
    case PAT_BLTZ:
    case PAT_BGTZ: {
      int rs;
      int32_t imm;
      uint32_t match = RV64I_MATCH_BEQ;
      if (s->operand_count != 2 ||
          !parse_register(s->operands[0].text, &rs) ||
          !resolve_offset(program, buf, s->operands[1].text, buf->byte_count,
                          &imm))
        return 0;
      switch (e->pattern) {
        case PAT_BEQZ: match = RV64I_MATCH_BEQ; return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_B, match, rs, 0, imm));
        case PAT_BNEZ: match = RV64I_MATCH_BNE; return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_B, match, rs, 0, imm));
        case PAT_BLEZ: match = RV64I_MATCH_BGE; return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_B, match, 0, rs, imm));
        case PAT_BGEZ: match = RV64I_MATCH_BGE; return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_B, match, rs, 0, imm));
        case PAT_BLTZ: match = RV64I_MATCH_BLT; return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_B, match, rs, 0, imm));
        case PAT_BGTZ: match = RV64I_MATCH_BLT; return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_B, match, 0, rs, imm));
        default: return 0;
      }
    }
    case PAT_BGT:
    case PAT_BLE:
    case PAT_BGTU:
    case PAT_BLEU: {
      int rs, rt;
      int32_t imm;
      uint32_t match = RV64I_MATCH_BLT;
      if (s->operand_count != 3 ||
          !parse_register(s->operands[0].text, &rs) ||
          !parse_register(s->operands[1].text, &rt) ||
          !resolve_offset(program, buf, s->operands[2].text, buf->byte_count,
                          &imm))
        return 0;
      switch (e->pattern) {
        case PAT_BGT:  match = RV64I_MATCH_BLT;  return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_B, match, rt, rs, imm));
        case PAT_BLE:  match = RV64I_MATCH_BGE;  return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_B, match, rt, rs, imm));
        case PAT_BGTU: match = RV64I_MATCH_BLTU; return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_B, match, rt, rs, imm));
        case PAT_BLEU: match = RV64I_MATCH_BGEU; return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_B, match, rt, rs, imm));
        default: return 0;
      }
    }
    case PAT_NEG:
    case PAT_NEGW:
    case PAT_NOT:
    case PAT_SEQZ:
    case PAT_SNEZ:
    case PAT_SGTZ:
    case PAT_SLTZ: {
      int rd, rs;
      if (s->operand_count != 2 ||
          !parse_register(s->operands[0].text, &rd) ||
          !parse_register(s->operands[1].text, &rs))
        return 0;
      switch (e->pattern) {
        case PAT_NEG:  return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SUB, rd, 0, rs));
        case PAT_NEGW: return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SUBW, rd, 0, rs));
        case PAT_NOT:  return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_XORI, rd, rs, -1));
        case PAT_SEQZ: return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_I, RV64I_MATCH_SLTIU, rd, rs, 1));
        case PAT_SNEZ: return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SLTU, rd, 0, rs));
        case PAT_SGTZ: return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SLT, rd, 0, rs));
        case PAT_SLTZ: return emit_word_raw(buf, rv64i_emit(RV64I_FORMAT_R, RV64I_MATCH_SLT, rd, rs, 0));
        default: return 0;
      }
    }
    default:
      return 0;
  }
}

static int second_pass_text(struct asm_program *program, struct byte_buffer *buf) {
  buf->byte_count = 0;

  for (uint32_t i = 0; i < program->statement_count; i++) {
    const struct asm_statement *s = &program->statements[i];

    switch (s->kind) {
      case ASM_STATEMENT_EQU:
      case ASM_STATEMENT_LABEL:
      case ASM_STATEMENT_NOP:
        break;

      case ASM_STATEMENT_BYTES:
        for (uint32_t j = 0; j < s->operand_count; j++) {
          int32_t val;
          if (!parse_value(program, s->operands[j].text, &val) ||
              !emit_byte(buf, (uint8_t)val))
            return 0;
        }
        break;

      case ASM_STATEMENT_DWORD: {
        int32_t val;
        int32_t label_off;
        if (s->operand_count != 1) return 0;
        if (parse_value(program, s->operands[0].text, &val)) {
          if (!emit_dword_raw(buf, (uint32_t)val)) return 0;
        } else {
          if (!lookup_label(buf, s->operands[0].text, &label_off)) return 0;
          if (!emit_dword_raw(buf, (uint32_t)label_off)) return 0;
        }
        break;
      }

      case ASM_STATEMENT_WORD: {
        if (s->operand_count == 1) {
          int32_t val;
          if (parse_value(program, s->operands[0].text, &val)) {
            if (!emit_word_raw(buf, (uint32_t)val)) return 0;
          } else {
            int32_t label_off;
            if (!lookup_label(buf, s->operands[0].text, &label_off)) return 0;
            if (!emit_word_raw(buf, (uint32_t)label_off)) return 0;
          }
        } else if (s->operand_count == 3 &&
                   strings_equal(s->operands[1].text, "-")) {
          int32_t left;
          if (strings_equal(s->operands[2].text, ".")) {
            if (!lookup_label(buf, s->operands[0].text, &left)) return 0;
            if (!emit_word_raw(buf, (uint32_t)(left - (int32_t)buf->byte_count)))
              return 0;
          } else {
            int32_t right;
            if (!lookup_label(buf, s->operands[0].text, &left) ||
                !lookup_label(buf, s->operands[2].text, &right))
              return 0;
            if (!emit_word_raw(buf, (uint32_t)(left - right))) return 0;
          }
        } else {
          return 0;
        }
        break;
      }

      case ASM_STATEMENT_STRING:
        if (s->operand_count != 1 || s->operands[0].kind != ASM_TOKEN_STRING)
          return 0;
        for (uint32_t j = 0; s->operands[0].text[j]; j++) {
          if (!emit_byte(buf, (uint8_t)s->operands[0].text[j])) return 0;
        }
        if (!emit_byte(buf, 0)) return 0;
        break;

      case ASM_STATEMENT_ALIGN: {
        uint32_t padding;
        if (!align_padding(buf->byte_count, 4u, &padding)) return 0;
        while (padding) {
          if (!emit_byte(buf, 0)) return 0;
          padding--;
        }
        break;
      }

      case ASM_STATEMENT_INSTR:
        if (!emit_instr(program, s, buf)) return 0;
        break;

      default:
        return 0;
    }
  }
  return 1;
}

/* ---- Public API ---- */

int compile_as0_program(const struct as0_program *program, struct code_sink *sink,
                        struct compile_diagnostics *diag) {
  struct asm_program *parsed = &g_as0_program_storage;
  struct byte_buffer *buffer = &g_as0_buffer_storage;

  buffer->byte_count = 0;
  buffer->label_count = 0;
  diag->bytes_emitted = 0;
  diag->words_emitted = 0;
  diag->fixups_applied = 0;

  if (!parse_text_source(program->source, parsed) ||
      !collect_defines(parsed))
    return 0;
  if (!first_pass_text(parsed, buffer) ||
      !second_pass_text(parsed, buffer))
    return 0;

  diag->bytes_emitted = buffer->byte_count;
  diag->words_emitted = buffer->byte_count / 4u;
  return flush_buffer_to_sink(buffer, sink, program->name, diag);
}
