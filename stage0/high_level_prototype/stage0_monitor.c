/* Copyright (C) 2026 Christian Westrom
 * This file is based on stage0_monitor.c from oriansj/stage0
 * Copyright (C) 2020 Jeremiah Orians
 *
 * stage0 is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * stage0 is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with stage0.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <stdint.h>

#define UART_BASE 0x10000000u
#define UART_LSR UART_BASE + 5u
#define UART_LSR_DATA_READY 0x01u
#define UART_LSR_THR_EMPTY 0x20u

#define CODE_BUFFER_MAX 0x1000u

extern uint8_t _stack_top;
extern uint8_t __bss_start;
extern uint8_t __bss_end;

static inline void uart_write(uint8_t value) {
  volatile uint8_t *lsr = (volatile uint8_t *)UART_LSR;
  while (0 == (*lsr & UART_LSR_THR_EMPTY)) {
  }
  *(volatile uint8_t *)UART_BASE = value;
}

static inline uint8_t uart_read(void) {
  volatile uint8_t *lsr = (volatile uint8_t *)UART_LSR;
  while (0 == (*lsr & UART_LSR_DATA_READY)) {
  }
  return *(volatile uint8_t *)UART_BASE;
}

static void line_comment(void) {
  int c = uart_read();
  uart_write((uint8_t)c);
  while ((10 != c) && (13 != c)) {
    c = uart_read();
    uart_write((uint8_t)c);
  }
}

static void display_newline(void) {
  uart_write(13);
  uart_write(10);
}

static int hex(int c) {
  /* Clear out line comments */
  if ((';' == c) || ('#' == c)) {
    line_comment();
    return -1;
  }

  /* Deal with non-hex chars*/
  if ('0' > c)
    return -1;

  /* Deal with 0-9 */
  if ('9' >= c)
    return (c - 48);

  /* Convert a-f to A-F*/
  c = c & 0xDF;

  /* Get rid of everything below A */
  if ('A' > c)
    return -1;

  /* Deal with A-F */
  if ('F' >= c)
    return (c - 55);

  /* Everything else is garbage */
  return -1;
}

/* Standard C main program */
static uint8_t code_buffer[CODE_BUFFER_MAX];

static void execute_code(void) { ((void (*)(void))code_buffer)(); }

int main(void) {
  int toggle = 0;
  int holder = 0;
  uint8_t *write_ptr = code_buffer;
  uint8_t *write_end = code_buffer + CODE_BUFFER_MAX;

  for (;;) {
    int c = uart_read();
    if (4 == c) {
      display_newline();
      execute_code();
      continue;
    }

    uart_write((uint8_t)c);
    int R0 = hex(c);
    if (0 <= R0) {
      if (toggle) {
        uint8_t byte = (uint8_t)(((holder & 0x0F) << 4) | (R0 & 0x0F));
        if (write_ptr < write_end) {
          *write_ptr++ = byte;
        }
        holder = 0;
      } else {
        holder = R0;
      }

      toggle = !toggle;
    }
  }
}

void _start(void) __attribute__((naked, section(".text.start")));
void _start(void) {
  __asm__ volatile("la sp, _stack_top\n"
                   "la t0, __bss_start\n"
                   "la t1, __bss_end\n"
                   "1:\n"
                   "bgeu t0, t1, 2f\n"
                   "sd zero, 0(t0)\n"
                   "addi t0, t0, 8\n"
                   "j 1b\n"
                   "2:\n"
                   "call main\n"
                   "3:\n"
                   "j 3b\n");
}