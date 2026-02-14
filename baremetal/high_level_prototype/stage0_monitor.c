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

/* Define code_buffer and stack in assembly to control memory layout.
 * This matches the layout in stage0/hex0.s:
 * - code_buffer: 4KB for storing loaded hex bytes
 * - stack: 4KB below code_buffer, grows downward from stack_top
 * Both must be defined together to prevent overlapping addresses.
 */
__asm__(".section .bss\n"
        ".balign 16\n"
        "code_buffer:\n"
        ".space 0x1000\n"
        "stack_bottom:\n"
        ".space 0x1000\n"
        "stack_top:\n");

extern uint8_t code_buffer[];
extern uint8_t stack_top;

static inline uint8_t uart_read(void) {
  volatile uint8_t *lsr = (volatile uint8_t *)UART_LSR;
  while (0 == (*lsr & UART_LSR_DATA_READY)) {
  }
  return *(volatile uint8_t *)UART_BASE;
}

static void line_comment(void) {
  int c = uart_read();
  while ((10 != c) && (13 != c)) {
    c = uart_read();
  }
}

static int hex(int c) {
  /* Clear out line comments */
  if ((';' == c) || ('#' == c)) {
    line_comment();
    return -1;
  }

  /* Deal with non-hex chars*/
  if ('0' > c) {
    return -1;
  }

  /* Deal with 0-9 */
  if ('9' >= c) {
    return (c - 48);
  }

  /* Convert a-f to A-F*/
  c = c & 0xDF;

  /* Get rid of everything below A */
  if ('A' > c) {
    return -1;
  }

  /* Deal with A-F */
  if ('F' >= c) {
    return (c - 55);
  }
  /* Everything else is garbage */
  return -1;
}

/* Entry point must be first in the binary so that when code_buffer is executed,
 * it starts here (not at main). This matches the assembly version layout.
 * We declare this first and put it in .text (not a subsection) to ensure it comes first.
 */
void _start(void) __attribute__((naked, section(".text")));
void _start(void) {
  /* Set up stack and call main.
   * Note: We rely on QEMU initializing RAM to zero, so no explicit BSS clearing.
   * This matches the assembly version in stage0/hex0.s.
   */
  __asm__ volatile("la sp, stack_top\n"      // Initialize stack pointer to top of stack
                   "call main\n"              // Call main function
                   "1:\n"
                   "j 1b\n");                 // Infinite loop when main returns
}

/* Execute the code loaded into code_buffer.
 * We use inline assembly to jump to the code_buffer address, matching the
 * behavior of the assembly version in stage0/hex0.s (lines 175-176).
 */
static void execute_code(void) {
  __asm__ volatile("la t0, code_buffer\n"
                   "jr t0\n");
}

int main(void) {
  int toggle = 0;
  int holder = 0;
  uint8_t *write_ptr = code_buffer;
  uint8_t *write_end = code_buffer + CODE_BUFFER_MAX;

  for (;;) {
    uint8_t c = uart_read();
    if (4 == c) {
      execute_code();
      continue;
    }

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
