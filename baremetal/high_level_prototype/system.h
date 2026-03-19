#ifndef BAREMETAL_HIGH_LEVEL_PROTOTYPE_SYSTEM_H
#define BAREMETAL_HIGH_LEVEL_PROTOTYPE_SYSTEM_H

#include <stdint.h>

#if !defined(SYSTEM_POSIX) && !defined(SYSTEM_QEMU_VIRT)
#define SYSTEM_QEMU_VIRT 1
#endif

#if defined(SYSTEM_POSIX)

#include <stdio.h>
#include <stdlib.h>

#ifndef SYSTEM_IMPLEMENTATION
#define SYSTEM_IMPLEMENTATION

static uint8_t uart_read(void) {
  int value = getchar();
  if (value == EOF) return 4u;
  return (uint8_t)value;
}

static void uart_write(uint8_t value) {
  fputc((int)value, stdout);
  fflush(stdout);
}

static void system_test_finisher_write(uint32_t value) {
  (void)value;
}

static void __attribute__((used, noinline, noreturn)) system_exit(int status) {
  fflush(stdout);
  fflush(stderr);
  exit(status);
}

static void __attribute__((used, noinline, noreturn)) system_die(void) {
  system_exit(1);
}

#endif // SYSTEM_IMPLEMENTATION

#elif defined(SYSTEM_QEMU_VIRT)

#define UART_BASE 0x10000000u
#define UART_LSR UART_BASE + 5u
#define UART_LSR_DATA_READY 0x01u
#define UART_LSR_THR_EMPTY 0x20u

#define TEST_FINISHER_BASE 0x00100000u
#define TEST_FINISHER_PASS 0x00005555u
#define TEST_FINISHER_FAIL 0x00003333u

#ifndef SYSTEM_IMPLEMENTATION
#define SYSTEM_IMPLEMENTATION

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

static void system_test_finisher_write(uint32_t value) {
  *(volatile uint32_t *)TEST_FINISHER_BASE = value;
}

static void __attribute__((used, noinline, noreturn)) system_exit(int status) {
  if (status == 0) {
    system_test_finisher_write(TEST_FINISHER_PASS);
  } else {
    uint32_t code = (uint32_t)status & 0xffffu;
    if (code == 0u) code = 1u;
    system_test_finisher_write((code << 16) | TEST_FINISHER_FAIL);
  }

  for (;;) {
  }
}

static void __attribute__((used, noinline, noreturn)) system_die(void) {
  system_exit(1);
}

#endif // SYSTEM_IMPLEMENTATION

#else
#error "Select exactly one system backend"
#endif

#endif // BAREMETAL_HIGH_LEVEL_PROTOTYPE_SYSTEM_H
