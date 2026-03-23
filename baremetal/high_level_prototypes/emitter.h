#ifndef BAREMETAL_HIGH_LEVEL_PROTOTYPE_EMITTER_H
#define BAREMETAL_HIGH_LEVEL_PROTOTYPE_EMITTER_H

#include <stdint.h>

struct as0_program {
  const char *name;
  const char *source;
};

struct compile_diagnostics {
  uint32_t words_emitted;
  uint32_t bytes_emitted;
  uint32_t fixups_applied;
};

struct code_sink;

typedef void (*sink_begin_program_fn)(struct code_sink *sink, const char *name);
typedef void (*sink_write_byte_fn)(struct code_sink *sink, uint8_t byte);
typedef void (*sink_end_program_fn)(struct code_sink *sink, const char *name,
                                    const struct compile_diagnostics *diag);

struct code_sink {
  sink_begin_program_fn begin_program;
  sink_write_byte_fn write_byte;
  sink_end_program_fn end_program;
  void *context;
};

int compile_as0_program(const struct as0_program *program, struct code_sink *sink,
                        struct compile_diagnostics *diag);

#endif
