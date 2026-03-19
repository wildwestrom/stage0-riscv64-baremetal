#ifndef BAREMETAL_HIGH_LEVEL_PROTOTYPE_EMITTER_INTERNAL_H
#define BAREMETAL_HIGH_LEVEL_PROTOTYPE_EMITTER_INTERNAL_H
#include <stdint.h>
#include "emitter.h"

enum { OUTPUT_MAX_BYTES = 65536, LABEL_MAX = 512, TOKEN_TEXT_MAX = 96 };

struct label_entry { char name[TOKEN_TEXT_MAX]; int32_t offset; };
struct byte_buffer {
  uint8_t bytes[OUTPUT_MAX_BYTES];
  uint32_t byte_count;
  struct label_entry labels[LABEL_MAX];
  uint32_t label_count;
};
#endif
