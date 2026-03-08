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
\ Control-flow words for DerzForth's threaded interpreter.
\ `branch` and `0branch` patch the saved instruction pointer on the return stack.
\ `lit` is used to treat an execution token as inline data so these immediate
\ words can compile branch primitives into the current definition.

: branch   rp@ @ dup @ + rp@ ! ;
: 0branch  0= rp@ @ swap over @ 4 - and + 4 + rp@ ! ;

: if       [ ' lit , ' 0branch , ] , here 0 , ; immediate
: then     dup here swap - swap ! ; immediate
: else     [ ' lit , ' branch , ] , here 0 , swap dup here swap - swap ! ; immediate
: begin    here ; immediate
: until    [ ' lit , ' 0branch , ] , here - , ; immediate

: recurse  latest 8 + , ; immediate
