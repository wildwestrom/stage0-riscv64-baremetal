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
\ Utility words and the first boxed-cell heap machinery for the Lisp layer.
\ Later phases can build the reader and evaluator on top of these definitions.

\ Small arithmetic and stack helpers missing from the upstream prelude.
: 1+    1 + ;
: 1-   -1 + ;
: 4+    4 + ;
: rot   >r swap r> swap ;
: -rot  swap >r swap r> ;
: <     - 0x80000000 and ;  \ signed less-than for small same-width values
: >=    < 0= ;
: 10*   dup 2* 2* + 2* ;

\ The Lisp heap lives at a conservative fixed address in RAM, away from the
\ loaded Forth dictionary and the temporary test words compiled afterward.
: heap-ptr   0x80000000 0x00010000 + ;
: heap-start heap-ptr 4 + ;
: lisp-init  heap-start heap-ptr ! ;

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

: cons         ( car cdr -- pair )     0 -rot make-cell ;
: make-fixnum  ( n -- value )          1 swap 0 make-cell ;
: make-symbol  ( hash name -- value )  2 -rot make-cell ;
: make-closure ( params body-env -- value ) 3 -rot make-cell ;
: make-builtin ( id -- value )         4 swap 0 make-cell ;

: first        ( pair -- car )   field1@ ;
: rest         ( pair -- cdr )   field2@ ;
: set-first!   ( value pair -- ) set-field1! ;
: set-rest!    ( value pair -- ) set-field2! ;
: fixnum>n     ( value -- n )    field1@ ;

: nil?      ( value -- flag ) 0= ;
: pair?     ( value -- flag ) dup nil? if drop 0 exit then tag@ 0= ;
: fixnum?   ( value -- flag ) dup nil? if drop 0 exit then tag@ 1 = ;
: symbol?   ( value -- flag ) dup nil? if drop 0 exit then tag@ 2 = ;
: closure?  ( value -- flag ) dup nil? if drop 0 exit then tag@ 3 = ;
: builtin?  ( value -- flag ) dup nil? if drop 0 exit then tag@ 4 = ;
: eq?       ( a b -- flag ) = ;
