#include <stdint.h>

#define UART_BASE 0x10000000u
#define UART_LSR UART_BASE + 5u
#define UART_LSR_DATA_READY 0x01u
#define UART_LSR_THR_EMPTY 0x20u

#ifndef UART_IMPLEMENTATION
#define UART_IMPLEMENTATION

static uint8_t uart_read(void) {
  volatile uint8_t *lsr = (volatile uint8_t *)UART_LSR;
  while (0 == (*lsr & UART_LSR_DATA_READY)) {
  }
  return *(volatile uint8_t *)UART_BASE;
}

static void uart_write(uint8_t value) {
  volatile uint8_t *lsr = (volatile uint8_t *)UART_LSR;
  while (0 == (*lsr & UART_LSR_THR_EMPTY)) {
  }
  *(volatile uint8_t *)UART_BASE = value;
}

#endif // UART_IMPLEMENTATION
