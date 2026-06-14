;*****************************************************************************
;* dct-mpeg2-64.asm: x86 MPEG-2 transforms
;*****************************************************************************
;* Copyright (C) 2003-2025 x264 project
;* Copyright (c) 2011 Ronald S. Bultje <rsbultje@gmail.com>
;* Copyright (c) 2015 Christophe Gisquet
;*
;* The IDCT is ported from FFmpeg's ProRes/Simple IDCT. It is identical to the
;* simple IDCT written by Michael Niedermayer except for the clip range. Only
;* the 8-bit add-to-destination path is kept here.
;*
;* This program is free software; you can redistribute it and/or modify
;* it under the terms of the GNU Lesser General Public License version 2.1
;* or later (the license of the ported FFmpeg sources), or, at your option,
;* the GNU General Public License version 2 or later.
;*
;* This program is distributed in the hope that it will be useful,
;* but WITHOUT ANY WARRANTY; without even the implied warranty of
;* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;* GNU General Public License for more details.
;*****************************************************************************

%include "x86inc.asm"
%include "x86util.asm"

%if HAVE_MPEG2 && !HIGH_BIT_DEPTH && ARCH_X86_64

SECTION_RODATA

cextern pw_32
pd_round_11: times 4 dd 1<<(11-1)

%macro CONST_DEC 3
const %1
times 4 dw %2, %3
%endmacro

%define W1sh2 22725 ; W1 = 90901 = 22725<<2 + 1
%define W2sh2 21407 ; W2 = 85627 = 21407<<2 - 1
%define W3sh2 19265 ; W3 = 77062 = 19265<<2 + 2
%define W3sh2_lo 19266
%define W4sh2_lo 16383
%define W5sh2 12873 ; W5 = 51491 = 12873<<2 - 1
%define W6sh2  8867 ; W6 = 35468 =  8867<<2
%define W7sh2  4520 ; W7 = 18081 =  4520<<2 + 1

CONST_DEC  w4_plus_w2,   W4sh2_lo, +W2sh2
CONST_DEC  w4_min_w2,    W4sh2_lo, -W2sh2
CONST_DEC  w4_plus_w6,   W4sh2_lo, +W6sh2
CONST_DEC  w4_min_w6,    W4sh2_lo, -W6sh2
CONST_DEC  w1_plus_w3,   W1sh2,    +W3sh2_lo
CONST_DEC  w3_min_w1,    W3sh2_lo, -W1sh2
CONST_DEC  w7_plus_w3,   W7sh2,    +W3sh2_lo
CONST_DEC  w3_min_w7,    W3sh2_lo, -W7sh2
CONST_DEC  w1_plus_w5,   W1sh2,    +W5sh2
CONST_DEC  w5_min_w1,    W5sh2,    -W1sh2
CONST_DEC  w5_plus_w7,   W5sh2,    +W7sh2
CONST_DEC  w7_min_w5,    W7sh2,    -W5sh2

; interleave data while maintaining source
; %1=type, %2=dstlo, %3=dsthi, %4=src, %5=interleave
%macro SBUTTERFLY3 5
    punpckl%1   m%2, m%4, m%5
    punpckh%1   m%3, m%4, m%5
%endmacro

; %1/%2=src1/dst1, %3/%4=dst2, %5/%6=src2, %7=shift
; action: %3/%4 = %1/%2 - %5/%6; %1/%2 += %5/%6
;         %1/%2/%3/%4 >>= %7; dword -> word (in %1/%3)
%macro SUMSUB_SHPK 7
    psubd       %3,  %1,  %5       ; { a0 - b0 }[0-3]
    psubd       %4,  %2,  %6       ; { a0 - b0 }[4-7]
    paddd       %1,  %5            ; { a0 + b0 }[0-3]
    paddd       %2,  %6            ; { a0 + b0 }[4-7]
    psrad       %1,  %7
    psrad       %2,  %7
    psrad       %3,  %7
    psrad       %4,  %7
    packssdw    %1,  %2            ; row[0]
    packssdw    %3,  %4            ; row[7]
%endmacro

; %1 = initial bias ("" if nop)
; %2 = number of bits to shift at the end
%macro IDCT_1D 2
%ifstr %1
    mova        m11, [pd_round_ %+ %2]
%else
    paddw       m10, [%1]
%endif
    SBUTTERFLY3 wd,  0,  1, 10,  8 ; { row[0], row[2] }[0-3]/[4-7]
    pmaddwd     m2,  m0, [w4_plus_w6]
    pmaddwd     m3,  m1, [w4_plus_w6]
    pmaddwd     m4,  m0, [w4_min_w6]
    pmaddwd     m5,  m1, [w4_min_w6]
    pmaddwd     m6,  m0, [w4_min_w2]
    pmaddwd     m7,  m1, [w4_min_w2]
    pmaddwd     m0, [w4_plus_w2]
    pmaddwd     m1, [w4_plus_w2]
%ifstr %1
    ; add the row-pass rounding bias (1 << (shift-1)) loaded in m11
    paddd       m2, m11
    paddd       m3, m11
    paddd       m4, m11
    paddd       m5, m11
    paddd       m6, m11
    paddd       m7, m11
    paddd       m0, m11
    paddd       m1, m11
%endif

    SBUTTERFLY3 wd,  8,  9, 13, 12 ; { row[4], row[6] }[0-3]/[4-7]
    pmaddwd     m10, m8, [w4_plus_w6]
    pmaddwd     m11, m9, [w4_plus_w6]
    paddd       m0,  m10            ; a0[0-3]
    paddd       m1,  m11            ; a0[4-7]
    pmaddwd     m10, m8, [w4_min_w6]
    pmaddwd     m11, m9, [w4_min_w6]
    paddd       m6,  m10           ; a3[0-3]
    paddd       m7,  m11           ; a3[4-7]
    pmaddwd     m10, m8, [w4_min_w2]
    pmaddwd     m11, m9, [w4_min_w2]
    pmaddwd     m8, [w4_plus_w2]
    pmaddwd     m9, [w4_plus_w2]
    psubd       m4,  m10           ; a2[0-3] intermediate
    psubd       m5,  m11           ; a2[4-7] intermediate
    psubd       m2,  m8            ; a1[0-3] intermediate
    psubd       m3,  m9            ; a1[4-7] intermediate

    ; load/store
    mova   [blockq+  0], m0
    mova   [blockq+ 32], m2
    mova   [blockq+ 64], m4
    mova   [blockq+ 96], m6
    mova        m10,[blockq+ 16]       ; { row[1] }[0-7]
    mova        m8, [blockq+ 48]       ; { row[3] }[0-7]
    mova        m13,[blockq+ 80]       ; { row[5] }[0-7]
    mova        m11,[blockq+112]       ; { row[7] }[0-7]
    mova   [blockq+ 16], m1
    mova   [blockq+ 48], m3
    mova   [blockq+ 80], m5
    mova   [blockq+112], m7

    SBUTTERFLY3 wd,  0,  1, 10, 8  ; { row[1], row[3] }[0-3]/[4-7]
    pmaddwd     m2,  m0, [w3_min_w7]
    pmaddwd     m3,  m1, [w3_min_w7]
    pmaddwd     m4,  m0, [w5_min_w1]
    pmaddwd     m5,  m1, [w5_min_w1]
    pmaddwd     m6,  m0, [w7_min_w5]
    pmaddwd     m7,  m1, [w7_min_w5]
    pmaddwd     m0, [w1_plus_w3]
    pmaddwd     m1, [w1_plus_w3]

    SBUTTERFLY3 wd,  8,  9, 13, 11 ; { row[5], row[7] }[0-3]/[4-7]

    pmaddwd     m10, m8, [w1_plus_w5]
    pmaddwd     m11, m9, [w1_plus_w5]
    pmaddwd     m12, m8, [w5_plus_w7]
    pmaddwd     m13, m9, [w5_plus_w7]
    psubd       m2,  m10           ; b1[0-3]
    psubd       m3,  m11           ; b1[4-7]
    paddd       m0,  m12            ; b0[0-3]
    paddd       m1,  m13            ; b0[4-7]
    pmaddwd     m12, m8, [w7_plus_w3]
    pmaddwd     m13, m9, [w7_plus_w3]
    pmaddwd     m8, [w3_min_w1]
    pmaddwd     m9, [w3_min_w1]
    paddd       m4,  m12           ; b2[0-3]
    paddd       m5,  m13           ; b2[4-7]
    paddd       m6,  m8            ; b3[0-3]
    paddd       m7,  m9            ; b3[4-7]

    mova        m8, [blockq+ 0]        ; a0[0-3]
    mova        m9, [blockq+16]        ; a0[4-7]
    SUMSUB_SHPK m8,  m9,  m10, m11, m0,  m1,  %2
    mova        m0, [blockq+32]        ; a1[0-3]
    mova        m1, [blockq+48]        ; a1[4-7]
    SUMSUB_SHPK m0,  m1,  m9,  m11, m2,  m3,  %2
    mova        m1, [blockq+64]        ; a2[0-3]
    mova        m2, [blockq+80]        ; a2[4-7]
    SUMSUB_SHPK m1,  m2,  m11, m3,  m4,  m5,  %2
    mova        m2, [blockq+96]        ; a3[0-3]
    mova        m3, [blockq+112]       ; a3[4-7]
    SUMSUB_SHPK m2,  m3,  m4,  m5,  m6,  m7,  %2
%endmacro

; %1 = row shift, %2 = row bias macro, %3 = column shift, %4 = column bias macro
%macro IDCT_FN 4
    mova        m10,[blockq+ 0]        ; { row[0] }[0-7]
    mova        m8, [blockq+32]        ; { row[2] }[0-7]
    mova        m13,[blockq+64]        ; { row[4] }[0-7]
    mova        m12,[blockq+96]        ; { row[6] }[0-7]

    ; DC-only shortcut.  When there is only a DC coefficient the C shifts the
    ; value and splats it to all coeffs rather than doing the full IDCT.  This
    ; differs on 8-bit because the coefficient is 16383 rather than 16384.
    por      m1,  m8, m13
    por      m1,  m12
    por      m1, [blockq+ 16]       ; { row[1] }[0-7]
    por      m1, [blockq+ 48]       ; { row[3] }[0-7]
    por      m1, [blockq+ 80]       ; { row[5] }[0-7]
    por      m1, [blockq+112]       ; { row[7] }[0-7]
    pxor     m2,  m2
    pcmpeqw  m1,  m2
    psllw   m15,  m10, 3
    pand    m15,  m1
%if avx_enabled
    pcmpeqb  m3,  m3
    pxor    m14,  m1, m3
%else
    pcmpeqb m14, m14
    pxor    m14,  m1
%endif

    IDCT_1D  %1,  %2

    pand     m8,  m14
    pand     m0,  m14
    por      m8,  m15
    por      m0,  m15
    pand     m1,  m14
    pand     m2,  m14
    por      m1,  m15
    por      m2,  m15
    pand     m4,  m14
    pand     m11, m14
    por      m4,  m15
    por      m11, m15
    pand     m9,  m14
    pand     m10, m14
    por      m9,  m15
    por      m10, m15

    ; transpose for second part of IDCT
    TRANSPOSE8x8W 8, 0, 1, 2, 4, 11, 9, 10, 3
    mova   [blockq+ 16], m0
    mova   [blockq+ 48], m2
    mova   [blockq+ 80], m11
    mova   [blockq+112], m10
    SWAP         8,  10
    SWAP         1,   8
    SWAP         4,  13
    SWAP         9,  12

    IDCT_1D     %3, %4
%endmacro

SECTION .text

%macro STORE_HI_LO 12
    movq   %1, %9
    movq   %3, %10
    movq   %5, %11
    movq   %7, %12
    movhps %2, %9
    movhps %4, %10
    movhps %6, %11
    movhps %8, %12
%endmacro

%macro LOAD_ZXBW_8 16
    pmovzxbw %1, %9
    pmovzxbw %2, %10
    pmovzxbw %3, %11
    pmovzxbw %4, %12
    pmovzxbw %5, %13
    pmovzxbw %6, %14
    pmovzxbw %7, %15
    pmovzxbw %8, %16
%endmacro

%macro LOAD_ZXBW_4 9
    movh %1, %5
    movh %2, %6
    movh %3, %7
    movh %4, %8
    punpcklbw %1, %9
    punpcklbw %2, %9
    punpcklbw %3, %9
    punpcklbw %4, %9
%endmacro

%define PASS4ROWS(base, stride, stride3) \
    [base], [base + stride], [base + 2*stride], [base + stride3]

%define PASS8ROWS(base, base3, stride, stride3) \
    [base],           [base  + stride],   [base  + 2*stride], [base3], \
    [base3 + stride], [base3 + 2*stride], [base3 + stride3],  [base3 + stride*4]

; void add8x8_idct_mpeg2( pixel *pixels, intptr_t stride, dctcoef block[64] )
; block must be pre-transposed (matches FF_IDCT_PERM_TRANSPOSE); the IDCT writes
; the residual into pixels with saturation, i.e. pixels = clip( pixels + idct ).
%macro ADD8X8_IDCT_MPEG2 0
cglobal add8x8_idct_mpeg2, 3, 5, 16, pixels, stride, block, stride3, base3
    IDCT_FN    "", 11, pw_32, 20
    lea stride3q, [3*strideq]
%if cpuflag(sse4)
    lea base3q, [pixelsq + stride3q]
    LOAD_ZXBW_8 m3, m5, m6, m7, m12, m13, m14, m15, PASS8ROWS(pixelsq, base3q, strideq, stride3q)
    paddsw m8, m3
    paddsw m0, m5
    paddsw m1, m6
    paddsw m2, m7
    paddsw m4, m12
    paddsw m11, m13
    paddsw m9, m14
    paddsw m10, m15
%else
    pxor m12, m12
    LOAD_ZXBW_4 m3, m5, m6, m7, PASS4ROWS(pixelsq, strideq, stride3q), m12
    paddsw m8, m3
    paddsw m0, m5
    paddsw m1, m6
    paddsw m2, m7
    lea base3q, [pixelsq + 4*strideq]
    LOAD_ZXBW_4 m3, m5, m6, m7, PASS4ROWS(base3q, strideq, stride3q), m12
    paddsw m4, m3
    paddsw m11, m5
    paddsw m9, m6
    paddsw m10, m7
    lea base3q, [pixelsq + stride3q]
%endif
    packuswb  m8, m0
    packuswb  m1, m2
    packuswb  m4, m11
    packuswb  m9, m10
    STORE_HI_LO PASS8ROWS(pixelsq, base3q, strideq, stride3q), m8, m1, m4, m9
    RET
%endmacro

INIT_XMM sse2
ADD8X8_IDCT_MPEG2
INIT_XMM sse4
ADD8X8_IDCT_MPEG2
INIT_XMM avx
ADD8X8_IDCT_MPEG2

%endif
