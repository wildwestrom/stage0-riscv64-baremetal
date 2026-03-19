#include "../baremetal/high_level_prototype/uart.h"

void _start(void) {
    while (1) {
        uint8_t c = uart_read();
        uart_write(c);
    }
}
