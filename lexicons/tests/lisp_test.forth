\ SPDX-FileCopyrightText: 2026 Christian Westrom
\ SPDX-License-Identifier: GPL-3.0-or-later
\
\ Boxed-cell, printer, and evaluator smoke tests for the current Lisp layer.

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

: test-print-pair
  lisp-init
  1 make-fixnum 2 make-fixnum cons lisp-print 10 emit ;
test-print-pair

: make-symbol-x
  4 alloc >r
  ch-x r@ c!
  0 r@ 1 + c!
  hash-init ch-x hash-char r> make-symbol ;

: expr-cons-12
  make-symbol-cons
  1 make-fixnum
  2 make-fixnum
  list3 ;

: test-eval-quote
  lisp-init
  make-symbol-quote
  1 make-fixnum 2 make-fixnum list2
  list2
  0 eval lisp-print 10 emit ;
test-eval-quote

: test-eval-cons
  lisp-init
  expr-cons-12
  0 eval lisp-print 10 emit ;
test-eval-cons

: test-eval-first
  lisp-init
  make-symbol-first expr-cons-12 list2
  0 eval lisp-print 10 emit ;
test-eval-first

: test-eval-nil?
  lisp-init
  make-symbol-nil? make-symbol-nil list2
  0 eval lisp-print 10 emit ;
test-eval-nil?

: test-eval-define
  lisp-init
  make-symbol-define
  make-symbol-x
  0x20 8 + 2 + make-fixnum
  list3
  0 eval lisp-print 10 emit
  make-symbol-x 0 eval lisp-print 10 emit ;
test-eval-define

: test-eval-lambda
  lisp-init
  make-symbol-lambda
  make-symbol-x list1
  make-symbol-x
  list3
  5 make-fixnum
  list2
  0 eval lisp-print 10 emit ;
test-eval-lambda

: test-read-number
  lisp-init
  lisp-read lisp-print 10 emit ;
test-read-number
42
: test-read-symbol
  lisp-init
  lisp-read lisp-print 10 emit ;
test-read-symbol
hello
: test-read-list
  lisp-init
  lisp-read lisp-print 10 emit ;
test-read-list
(1 2 3)
: test-read-nested
  lisp-init
  lisp-read lisp-print 10 emit ;
test-read-nested
((1 2) 3)
: test-repl-quote
  lisp-init
  lisp-read global-env @ eval lisp-print 10 emit ;
test-repl-quote
(quote (1 2))
bye
