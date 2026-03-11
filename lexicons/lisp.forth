\ SPDX-FileCopyrightText: 2026 Christian Westrom
\ SPDX-License-Identifier: GPL-3.0-or-later
\
\\ Copyright (C) 2026 Christian Westrom
\\ This file is part of stage0.
\\
\\ stage0 is free software: you can redistribute it and/or modify
\\ it under the terms of the GNU General Public License as published by
\\ the Free Software Foundation, either version 3 of the License, or
\\ (at your option) any later version.
\\
\\ stage0 is distributed in the hope that it will be useful,
\\ but WITHOUT ANY WARRANTY; without even the implied warranty of
\\ MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
\\ GNU General Public License for more details.
\\
\\ You should have received a copy of the GNU General Public License
\\ along with stage0.  If not, see <http://www.gnu.org/licenses/>.
\
\ The boxed-cell substrate now includes enough Lisp support to evaluate small
\ hand-built forms. The raw `key`-driven reader from PLAN.md is still a later
\ step; this file focuses on symbols, environments, printing, and evaluation.

\ Small arithmetic and stack helpers missing from the upstream prelude.
: 1+    1 + ;
: 1-   -1 + ;
: 4+    4 + ;
\ `r@` is itself a colon word here, so `enter` has already pushed its own return
\ address. Skip that frame to reach the caller's top return-stack item.
: r@    rp@ 4 - @ ;
: rot   >r swap r> swap ;
: -rot  swap >r swap r> ;
: <     - 0x80000000 and ;  \ signed less-than for small same-width values
: >=    < 0= ;
: 10*   dup 2* 2* + 2* ;

\ Character constants used by symbol constructors and printing.
: ch-space 0x20 ;
: ch-!     0x20 1 + ;
: ch-lparen 0x20 8 + ;
: ch-rparen ch-lparen 1 + ;
: ch--     0x20 8 + 4 + 1 + ;
: ch-.     0x20 8 + 4 + 2 + ;
: ch-0     0x20 0x10 + ;
: ch-?     0x20 0x10 + 8 + 4 + 2 + 1 + ;

: ch-a 0x40 0x20 + 1 + ;
: ch-b ch-a 1 + ;
: ch-c ch-b 1 + ;
: ch-d ch-c 1 + ;
: ch-e ch-d 1 + ;
: ch-f ch-e 1 + ;
: ch-i ch-f 3 + ;
: ch-l ch-i 3 + ;
: ch-m ch-l 1 + ;
: ch-n ch-m 1 + ;
: ch-o ch-n 1 + ;
: ch-p ch-o 1 + ;
: ch-q ch-p 1 + ;
: ch-r ch-q 1 + ;
: ch-s ch-r 1 + ;
: ch-t ch-s 1 + ;
: ch-u ch-t 1 + ;
: ch-x ch-u 3 + ;

\ The Lisp heap lives well above DerzForth's growing dictionary so evaluator
\ allocations during tests cannot scribble over later word definitions.
: heap-ptr    0x80000000 0x00020000 + ;
: global-env  heap-ptr 4 + ;
: true-symbol heap-ptr 8 + ;
: nil-symbol  heap-ptr 0x0c + ;
: lookahead   heap-ptr 0x10 + ;
: heap-start  heap-ptr 0x14 + ;

: alloc ( size -- addr )
  heap-ptr @ dup rot + heap-ptr ! ;

\ Boxed Lisp values are 12-byte cells:
\   [ type : 4 ][ field1 : 4 ][ field2 : 4 ]
: make-cell ( type field1 field2 -- cell )
  12 alloc >r
  r> dup >r 8 + !
  r> dup >r 4 + !
  r> !
  heap-ptr @ 12 - ;

: tag@         ( cell -- tag )   @ ;
: field1@      ( cell -- field ) 4 + @ ;
: field2@      ( cell -- field ) 8 + @ ;
: set-field1!  ( value cell -- ) 4 + ! ;
: set-field2!  ( value cell -- ) 8 + ! ;

: cons         ( car cdr -- pair )          0 -rot make-cell ;
: make-fixnum  ( n -- value )               1 swap 0 make-cell ;
: make-symbol  ( hash name -- value )       2 -rot make-cell ;
: make-closure ( params body-env -- value ) 3 -rot make-cell ;

: first        ( pair -- car )   field1@ ;
: rest         ( pair -- cdr )   field2@ ;
: set-first!   ( value pair -- ) set-field1! ;
: set-rest!    ( value pair -- ) set-field2! ;
: fixnum>n     ( value -- n )    field1@ ;
: symbol-hash@ ( symbol -- hash ) field1@ ;
: symbol-name@ ( symbol -- addr ) field2@ ;
: closure-params ( closure -- params ) field1@ ;
: closure-body   ( closure -- body )   field2@ first ;
: closure-env    ( closure -- env )    field2@ rest ;

: nil?      ( value -- flag ) 0= ;
: pair?     ( value -- flag ) dup nil? if drop 0 exit then tag@ 0= ;
: fixnum?   ( value -- flag ) dup nil? if drop 0 exit then tag@ 1 = ;
: symbol?   ( value -- flag ) dup nil? if drop 0 exit then tag@ 2 = ;
: closure?  ( value -- flag ) dup nil? if drop 0 exit then tag@ 3 = ;
: eq?       ( a b -- flag ) = ;

: second ( list -- value ) rest first ;
: third  ( list -- value ) rest rest first ;
: fourth ( list -- value ) rest rest rest first ;
: list1  ( a -- list ) 0 cons ;
: list2  ( a b -- list ) 0 cons cons ;
: list3  ( a b c -- list ) 0 cons cons cons ;
: binding-key   ( binding -- symbol ) first ;
: binding-value ( binding -- value )  rest ;

\ The runtime uses the same 32-bit wrapped djb2 hash as the assembly dictionary.
: hash-init
  0x00001000 0x00000400 or 0x00000100 or 0x00000004 or 0x00000001 or ;

: hash-char ( hash char -- hash' )
  swap dup 2* 2* 2* 2* 2* + + ;

: hash-quote  hash-init ch-q hash-char ch-u hash-char ch-o hash-char ch-t hash-char ch-e hash-char ;
: hash-if     hash-init ch-i hash-char ch-f hash-char ;
: hash-define hash-init ch-d hash-char ch-e hash-char ch-f hash-char ch-i hash-char ch-n hash-char ch-e hash-char ;
: hash-lambda hash-init ch-l hash-char ch-a hash-char ch-m hash-char ch-b hash-char ch-d hash-char ch-a hash-char ;
: hash-t      hash-init ch-t hash-char ;
: hash-nil    hash-init ch-n hash-char ch-i hash-char ch-l hash-char ;
: hash-cons   hash-init ch-c hash-char ch-o hash-char ch-n hash-char ch-s hash-char ;
: hash-first  hash-init ch-f hash-char ch-i hash-char ch-r hash-char ch-s hash-char ch-t hash-char ;
: hash-rest   hash-init ch-r hash-char ch-e hash-char ch-s hash-char ch-t hash-char ;
: hash-pair?  hash-init ch-p hash-char ch-a hash-char ch-i hash-char ch-r hash-char ch-? hash-char ;
: hash-nil?   hash-init ch-n hash-char ch-i hash-char ch-l hash-char ch-? hash-char ;
: hash-eq?    hash-init ch-e hash-char ch-q hash-char ch-? hash-char ;

\ Small symbol constructors keep quoted forms and tests readable.
: make-symbol-t
  4 alloc >r
  ch-t r@ c!
  0 r@ 1 + c!
  hash-t r> make-symbol ;

: make-symbol-nil
  4 alloc >r
  ch-n r@ c!
  ch-i r@ 1 + c!
  ch-l r@ 2 + c!
  0 r@ 3 + c!
  hash-nil r> make-symbol ;

: make-symbol-quote
  8 alloc >r
  ch-q r@ c!
  ch-u r@ 1 + c!
  ch-o r@ 2 + c!
  ch-t r@ 3 + c!
  ch-e r@ 4 + c!
  0 r@ 5 + c!
  hash-quote r> make-symbol ;

: make-symbol-if
  4 alloc >r
  ch-i r@ c!
  ch-f r@ 1 + c!
  0 r@ 2 + c!
  hash-if r> make-symbol ;

: make-symbol-define
  8 alloc >r
  ch-d r@ c!
  ch-e r@ 1 + c!
  ch-f r@ 2 + c!
  ch-i r@ 3 + c!
  ch-n r@ 4 + c!
  ch-e r@ 5 + c!
  0 r@ 6 + c!
  hash-define r> make-symbol ;

: make-symbol-lambda
  8 alloc >r
  ch-l r@ c!
  ch-a r@ 1 + c!
  ch-m r@ 2 + c!
  ch-b r@ 3 + c!
  ch-d r@ 4 + c!
  ch-a r@ 5 + c!
  0 r@ 6 + c!
  hash-lambda r> make-symbol ;

: make-symbol-cons
  8 alloc >r
  ch-c r@ c!
  ch-o r@ 1 + c!
  ch-n r@ 2 + c!
  ch-s r@ 3 + c!
  0 r@ 4 + c!
  hash-cons r> make-symbol ;

: make-symbol-first
  8 alloc >r
  ch-f r@ c!
  ch-i r@ 1 + c!
  ch-r r@ 2 + c!
  ch-s r@ 3 + c!
  ch-t r@ 4 + c!
  0 r@ 5 + c!
  hash-first r> make-symbol ;

: make-symbol-rest
  8 alloc >r
  ch-r r@ c!
  ch-e r@ 1 + c!
  ch-s r@ 2 + c!
  ch-t r@ 3 + c!
  0 r@ 4 + c!
  hash-rest r> make-symbol ;

: make-symbol-pair?
  8 alloc >r
  ch-p r@ c!
  ch-a r@ 1 + c!
  ch-i r@ 2 + c!
  ch-r r@ 3 + c!
  ch-? r@ 4 + c!
  0 r@ 5 + c!
  hash-pair? r> make-symbol ;

: make-symbol-nil?
  8 alloc >r
  ch-n r@ c!
  ch-i r@ 1 + c!
  ch-l r@ 2 + c!
  ch-? r@ 3 + c!
  0 r@ 4 + c!
  hash-nil? r> make-symbol ;

: make-symbol-eq?
  8 alloc >r
  ch-e r@ c!
  ch-q r@ 1 + c!
  ch-? r@ 2 + c!
  0 r@ 3 + c!
  hash-eq? r> make-symbol ;

\ Environments are lists of binding pairs: ((symbol . value) ...)
\ These helpers stay on the data stack because DerzForth's structured control
\ flow rewrites the top of the return stack in-place.
: env-find-hash ( hash env -- binding|0 )
  dup nil? if 2drop 0 exit then
  over over first binding-key symbol-hash@ =
  if swap drop first exit then
  over swap rest nip recurse ;

: env-find ( symbol env -- binding|0 )
  over symbol-hash@ rot drop swap env-find-hash ;

: resolve-binding ( symbol env -- binding|0 )
  2dup env-find dup nil?
  if
    drop drop
    dup symbol-hash@ swap drop
    global-env @ env-find-hash
    exit
  then
  -rot 2drop ;

: bind-global ( symbol value -- value )
  2dup cons global-env @ cons global-env !
  nip ;

\ Lambda application currently only needs one positional binding for the tests:
\ build (symbol . value) and cons it onto the captured environment.
: extend-env1 ( value symbol env -- env' )
  >r
  swap cons
  r> cons ;

: lisp-true ( -- value )
  true-symbol @ dup nil?
  if drop make-symbol-t dup true-symbol ! exit then ;
: bool>lisp ( flag -- value ) if lisp-true exit then 0 ;

\ The printer stays self-recursive so pairs can print nested values without
\ needing a forward declaration to another word.
: divmod10 ( n -- q r )
  0 swap
  begin
    dup 10 < if exit then
    10 - swap 1+ swap
    0
  until ;

: print-number ( n -- )
  dup 0 < if ch-- emit negate recurse exit then
  dup 10 < if ch-0 + emit exit then
  divmod10 >r recurse r> ch-0 + emit ;

: print-string ( addr -- )
  dup c@ dup 0= if 2drop exit then
  emit
  1 + recurse ;

: print-nil ( -- )
  ch-n emit ch-i emit ch-l emit ;

: lisp-print ( value -- )
  dup nil? if drop print-nil exit then
  dup fixnum? if fixnum>n print-number exit then
  dup symbol? if symbol-name@ print-string exit then
  dup pair? if
    ch-lparen emit
    begin
      dup first recurse
      rest
      dup nil? if drop ch-rparen emit exit then
      dup pair? if ch-space emit 0 else ch-space emit ch-. emit ch-space emit recurse ch-rparen emit -1 then
    until
    exit
  then
  drop
  ch-? emit ;

\ `eval` keeps `env` on the data stack. In this system `if`/`until` patch the
\ saved instruction pointer at the top of the return stack, so `>r` cannot hold
\ Lisp data across structured control flow without corrupting execution.
: eval ( expr env -- value )
  over nil? if drop exit then
  over fixnum? if drop exit then
  over symbol? if
    over symbol-hash@ hash-nil = if 2drop 0 exit then
    over symbol-hash@ hash-t = if 2drop lisp-true exit then
    resolve-binding dup nil? if drop 0 exit then binding-value exit
  then

  over first dup symbol?
  if
    dup symbol-hash@ hash-quote = if
      drop
      drop
      second
      exit
    then
    dup symbol-hash@ hash-if = if
      drop
      2dup swap second swap recurse nil?
      if over fourth swap recurse nip exit then
      over third swap recurse nip exit
    then
    dup symbol-hash@ hash-define = if
      drop
      2dup swap third swap recurse
      -rot drop second swap
      bind-global
      exit
    then
    dup symbol-hash@ hash-lambda = if
      drop
      2dup swap third swap cons
      -rot drop second swap
      make-closure
      exit
    then
    dup symbol-hash@ hash-cons = if
      drop
      2dup swap second swap recurse
      -rot swap third swap recurse
      cons
      exit
    then
    dup symbol-hash@ hash-first = if
      drop
      2dup swap second swap recurse
      nip nip
      first
      exit
    then
    dup symbol-hash@ hash-rest = if
      drop
      2dup swap second swap recurse
      nip nip
      rest
      exit
    then
    dup symbol-hash@ hash-pair? = if
      drop
      2dup swap second swap recurse
      nip nip
      pair?
      bool>lisp
      exit
    then
    dup symbol-hash@ hash-nil? = if
      drop
      2dup swap second swap recurse
      nip nip
      nil?
      bool>lisp
      exit
    then
    dup symbol-hash@ hash-eq? = if
      drop
      2dup swap second swap recurse
      -rot swap third swap recurse
      eq?
      bool>lisp
      exit
    then
  then
  drop

  over first over recurse
  dup closure? if
    -rot over second swap recurse
    swap drop
    swap
    dup closure-body >r
    dup closure-env >r
    closure-params first
    r> extend-env1
    r> swap
    recurse
    exit
  then

  2drop
  0 ;

\ The global environment only needs `t` and `nil` so far. Builtins are handled
\ directly by `eval` until the raw reader and a more general applicative layer
\ exist.
: lisp-init ( -- )
  heap-start heap-ptr !
  0 global-env !
  0 true-symbol !
  0 nil-symbol !
  -1 lookahead ! ;

\ ===== Reader =====
\ Reads S-expressions character-by-character via `key`, building boxed cells.
\ A single-character lookahead buffer handles the common case where a delimiter
\ is read one character past the end of an atom.

\ Additional character constants for the reader.
: ch-tab     9 ;
: ch-newline 10 ;
: ch-cr      0x0c 1 + ;
: ch-9       ch-0 9 + ;

\ Whitespace test.
: ws? ( char -- flag )
  dup ch-space = if drop -1 exit then
  dup ch-tab = if drop -1 exit then
  dup ch-newline = if drop -1 exit then
  ch-cr = ;

\ Read one character, checking the lookahead buffer first.
: read-char ( -- char )
  lookahead @ dup -1 = if drop key exit then
  -1 lookahead ! ;

\ Push one character back into the lookahead buffer.
: unread-char ( char -- )
  lookahead ! ;

\ Skip whitespace characters, return the first non-whitespace char.
: skip-ws ( -- char )
  read-char
  dup ws? 0= if exit then
  drop recurse ;

\ Digit test: is char in '0'..'9'?
: digit? ( char -- flag )
  dup ch-0 < if drop 0 exit then
  ch-9 1+ < ;

\ Accumulate decimal digits into a number. Reads chars until non-digit.
: acc-digits ( n -- n )
  read-char dup digit?
  if ch-0 - swap 10* + recurse exit then
  unread-char ;

\ Test whether a character is a symbol-terminating delimiter.
: sym-delim? ( char -- flag )
  dup ws? if drop -1 exit then
  dup ch-rparen = if drop -1 exit then
  ch-lparen = ;

\ Align heap pointer up to next 4-byte boundary.
: align-heap ( -- )
  heap-ptr @ 3 + 3 invert and heap-ptr ! ;

\ Store one byte at heap-ptr, advance heap-ptr, update hash.
: store-and-hash ( name-start hash char -- name-start hash' )
  dup heap-ptr @ c!
  heap-ptr @ 1+ heap-ptr !
  hash-char ;

\ Null-terminate the symbol name, align heap, create symbol cell.
: finish-symbol ( name-start hash -- symbol )
  0 heap-ptr @ c!
  heap-ptr @ 1+ heap-ptr !
  align-heap
  swap make-symbol ;

\ Read remaining symbol characters, building hash and storing name.
: read-sym-loop ( name-start hash -- symbol )
  read-char dup sym-delim?
  if unread-char finish-symbol exit then
  store-and-hash recurse ;

\ Read a complete symbol starting from its first character.
: read-symbol ( first-char -- symbol )
  heap-ptr @        \ save name start address
  swap              \ ( name-start first-char )
  hash-init swap    \ ( name-start hash first-char )
  store-and-hash    \ ( name-start hash' )
  read-sym-loop ;

\ Read an atom (number or symbol) starting from its first character.
: read-atom ( first-char -- value )
  dup digit? if
    ch-0 - acc-digits make-fixnum exit
  then
  read-symbol ;

\ Read a list. Inlines the lisp-read dispatch to avoid forward references
\ (lisp-read would need to call read-list, and read-list calls lisp-read).
: read-list ( -- val )
  skip-ws
  dup ch-rparen = if drop 0 exit then
  dup ch-lparen = if
    drop
    recurse         \ read the sub-list
    recurse         \ read the rest of the outer list
    cons exit
  then
  read-atom         \ parse atom
  recurse           \ read the rest of the list
  cons ;

\ Top-level reader: skip whitespace, dispatch on '(' or atom.
: lisp-read ( -- val )
  skip-ws
  dup ch-lparen = if drop read-list exit then
  read-atom ;

\ Read-eval-print loop. Loops forever (exit by terminating QEMU).
: lisp-repl ( -- )
  begin
    lisp-read global-env @ eval lisp-print 10 emit
    0
  until ;
