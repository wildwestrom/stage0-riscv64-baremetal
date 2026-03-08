\ SPDX-FileCopyrightText: 2026 Christian Westrom
\ SPDX-License-Identifier: GPL-3.0-or-later
\
\ Control-flow smoke tests for the parent-owned DerzForth lexicons.

: test-if 1 if 0x40 1 + emit then ;
test-if

: test-else 0 if 0x40 1 + emit else 0x40 2 + emit then ;
test-else

: test-begin 3 begin 1 - dup 0= until drop 0x40 3 + emit ;
test-begin

bye
