#include <stdint.h>

#include "emitter.h"
#include "system.h"

enum { SELFHOST_SOURCE_MAX = 131072 };

static char g_selfhost_source[SELFHOST_SOURCE_MAX];

static int read_source_from_uart(char *dst, uint32_t capacity) {
  uint32_t used = 0;

  for (;;) {
    uint8_t byte = uart_read();

    if (byte == 4u) {
      if (used >= capacity) return 0;
      dst[used] = '\0';
      return 1;
    }

    if (used + 1u >= capacity) return 0;
    dst[used++] = (char)byte;
  }
}

static void raw_uart_sink_begin_program(struct code_sink *sink, const char *name) {
  (void)sink;
  (void)name;
}

static void raw_uart_sink_write_byte(struct code_sink *sink, uint8_t byte) {
  (void)sink;
  uart_write(byte);
}

static void raw_uart_sink_end_program(struct code_sink *sink, const char *name,
                                      const struct compile_diagnostics *diag) {
  (void)sink;
  (void)name;
  (void)diag;
}

int main(void) {
  struct as0_program program;
  struct code_sink sink;
  struct compile_diagnostics diag;

  program.name = "as0";
  program.source = g_selfhost_source;

  sink.begin_program = raw_uart_sink_begin_program;
  sink.write_byte = raw_uart_sink_write_byte;
  sink.end_program = raw_uart_sink_end_program;
  sink.context = 0;

  if (!read_source_from_uart(g_selfhost_source, SELFHOST_SOURCE_MAX)) return 1;

  if (!compile_as0_program(&program, &sink, &diag)) return 1;

  return 0;
}
