\ SPDX-FileCopyrightText: 2026 Christian Westrom
\ SPDX-License-Identifier: GPL-3.0-or-later
\
\ Boxed-cell and allocator smoke tests for the early Lisp substrate.

: test-fixnum
  lisp-init
  5 make-fixnum dup fixnum?
  if dup fixnum>n 5 = if 0x40 1 + emit then then
  drop ;
test-fixnum

: test-pair
  lisp-init
  1 make-fixnum 2 make-fixnum cons dup pair?
  if dup first fixnum>n 1 =
     if dup rest fixnum>n 2 = if 0x40 2 + emit then then
  then
  drop ;
test-pair

: test-nil
  0 nil?
  if 0x40 3 + emit then ;
test-nil

: test-setters
  lisp-init
  1 make-fixnum 2 make-fixnum cons
  dup 3 make-fixnum over set-first!
  dup first fixnum>n 3 =
  if 0x40 4 + emit then
  drop ;
test-setters

: test-alloc
  lisp-init
  12 alloc 12 alloc swap - 12 =
  if 0x40 5 + emit then ;
test-alloc

bye
