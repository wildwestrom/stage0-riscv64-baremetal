#ifndef BAREMETAL_HIGH_LEVEL_PROTOTYPE_HARNESS_COMMON_H
#define BAREMETAL_HIGH_LEVEL_PROTOTYPE_HARNESS_COMMON_H

#include <stdint.h>
#include "emitter.h"   /* struct compile_diagnostics, struct code_sink */

enum { CAPTURE_MAX_BYTES = 1024 };

struct capture_sink_context {
  uint8_t bytes[CAPTURE_MAX_BYTES];
  uint32_t byte_count;
};

extern struct capture_sink_context g_capture;

void uart_write_str(const char *text);

void capture_sink_begin_program(struct code_sink *sink, const char *name);
void capture_sink_write_byte(struct code_sink *sink, uint8_t byte);
void capture_sink_end_program(struct code_sink *sink, const char *name,
                              const struct compile_diagnostics *diag);
void dump_capture(const char *name, const struct capture_sink_context *capture,
                  const struct compile_diagnostics *diag);

#endif
