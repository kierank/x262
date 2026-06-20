;*****************************************************************************
;* quant-a.asm: x86 quantization and level-run
;*****************************************************************************
;* Copyright (C) 2005-2025 x264 project
;*
;* Authors: Loren Merritt <lorenm@u.washington.edu>
;*          Fiona Glaser <fiona@x264.com>
;*          Christian Heine <sennindemokrit@gmx.net>
;*          Oskar Arvidsson <oskar@irock.se>
;*          Henrik Gramner <henrik@gramner.com>
;*
;* This program is free software; you can redistribute it and/or modify
;* it under the terms of the GNU General Public License as published by
;* the Free Software Foundation; either version 2 of the License, or
;* (at your option) any later version.
;*
;* This program is distributed in the hope that it will be useful,
;* but WITHOUT ANY WARRANTY; without even the implied warranty of
;* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;* GNU General Public License for more details.
;*
;* You should have received a copy of the GNU General Public License
;* along with this program; if not, write to the Free Software
;* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02111, USA.
;*
;* This program is also available under a commercial proprietary license.
;* For more information, contact us at licensing@x264.com.
;*****************************************************************************

%include "x86inc.asm"
%include "x86util.asm"

SECTION_RODATA 64

%if HIGH_BIT_DEPTH
decimate_shuf_avx512: dd 0, 4, 8,12, 1, 5, 9,13, 2, 6,10,14, 3, 7,11,15
%else
dequant_shuf_avx512: dw  0, 2, 4, 6, 8,10,12,14,16,18,20,22,24,26,28,30
                     dw 32,34,36,38,40,42,44,46,48,50,52,54,56,58,60,62
levelrun_reverse_avx512: dw 31,30,29,28,27,26,25,24,23,22,21,20,19,18,17,16
                        dw 15,14,13,12,11,10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0
mpeg2_clip_max: times 32 dw 2047
mpeg2_clip_min: times 32 dw -2048
mpeg2_dc_summask: dw 0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
ALIGN 64
; reverse 8 qwords (for aligning the backward-indexed rl window with forward p)
trellis_rev8_q: dq 7, 6, 5, 4, 3, 2, 1, 0
; per-lane index ramp 0..7 (added into the packed key's low bits)
trellis_idx8_q: dq 0, 1, 2, 3, 4, 5, 6, 7
; byte iota 0..63 (compressed by the scan-order nonzero mask into the trellis
; candidate list)
trellis_iota_b: db  0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,15
                db 16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
                db 32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47
                db 48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63
%endif

%macro DQM4 3
    dw %1, %2, %1, %2, %2, %3, %2, %3
%endmacro
%macro DQM8 6
    dw %1, %4, %5, %4, %1, %4, %5, %4
    dw %4, %2, %6, %2, %4, %2, %6, %2
    dw %5, %6, %3, %6, %5, %6, %3, %6
    dw %4, %2, %6, %2, %4, %2, %6, %2
%endmacro

dequant8_scale:
    DQM8 20, 18, 32, 19, 25, 24
    DQM8 22, 19, 35, 21, 28, 26
    DQM8 26, 23, 42, 24, 33, 31
    DQM8 28, 25, 45, 26, 35, 33
    DQM8 32, 28, 51, 30, 40, 38
    DQM8 36, 32, 58, 34, 46, 43

dequant4_scale:
    DQM4 10, 13, 16
    DQM4 11, 14, 18
    DQM4 13, 16, 20
    DQM4 14, 18, 23
    DQM4 16, 20, 25
    DQM4 18, 23, 29

decimate_mask_table4:
    db  0,3,2,6,2,5,5,9,1,5,4,8,5,8,8,12,1,4,4,8,4,7,7,11,4,8,7,11,8,11,11,15,1,4
    db  3,7,4,7,7,11,3,7,6,10,7,10,10,14,4,7,7,11,7,10,10,14,7,11,10,14,11,14,14
    db 18,0,4,3,7,3,6,6,10,3,7,6,10,7,10,10,14,3,6,6,10,6,9,9,13,6,10,9,13,10,13
    db 13,17,4,7,6,10,7,10,10,14,6,10,9,13,10,13,13,17,7,10,10,14,10,13,13,17,10
    db 14,13,17,14,17,17,21,0,3,3,7,3,6,6,10,2,6,5,9,6,9,9,13,3,6,6,10,6,9,9,13
    db  6,10,9,13,10,13,13,17,3,6,5,9,6,9,9,13,5,9,8,12,9,12,12,16,6,9,9,13,9,12
    db 12,16,9,13,12,16,13,16,16,20,3,7,6,10,6,9,9,13,6,10,9,13,10,13,13,17,6,9
    db  9,13,9,12,12,16,9,13,12,16,13,16,16,20,7,10,9,13,10,13,13,17,9,13,12,16
    db 13,16,16,20,10,13,13,17,13,16,16,20,13,17,16,20,17,20,20,24

chroma_dc_dct_mask_mmx: dw 0, 0,-1,-1, 0, 0,-1,-1
chroma_dc_dmf_mask_mmx: dw 0, 0,-1,-1, 0,-1,-1, 0
chroma_dc_dct_mask:     dw 1, 1,-1,-1, 1, 1,-1,-1
chroma_dc_dmf_mask:     dw 1, 1,-1,-1, 1,-1,-1, 1

%if HIGH_BIT_DEPTH==0
dct_coef_shuffle:
%macro DCT_COEF_SHUFFLE 8
    %assign y x
    %rep 8
        %rep 7
            %rotate (~(y>>7))&1
            %assign y y<<((~(y>>7))&1)
        %endrep
        db %1*2
        %rotate 1
        %assign y y<<1
    %endrep
%endmacro
%assign x 0
%rep 256
    DCT_COEF_SHUFFLE 7, 6, 5, 4, 3, 2, 1, 0
%assign x x+1
%endrep
%endif

SECTION .text

cextern pb_1
cextern pw_1
cextern pw_2
cextern pw_256
cextern pd_1
cextern pb_01
cextern pd_1024
cextern deinterleave_shufd
cextern popcnt_table

%macro QUANT_DC_START 2
    movd      xm%1, r1m     ; mf
    movd      xm%2, r2m     ; bias
%if cpuflag(avx2)
    vpbroadcastdct m%1, xm%1
    vpbroadcastdct m%2, xm%2
%elif HIGH_BIT_DEPTH
    SPLATD     m%1, m%1
    SPLATD     m%2, m%2
%elif cpuflag(sse4) ; ssse3, but not faster on conroe
    mova       m5, [pb_01]
    pshufb     m%1, m5
    pshufb     m%2, m5
%else
    SPLATW     m%1, m%1
    SPLATW     m%2, m%2
%endif
%endmacro

%macro QUANT_END 0
    xor      eax, eax
%if cpuflag(sse4)
    ptest     m5, m5
%else ; !sse4
%if ARCH_X86_64
%if mmsize == 16
    packsswb  m5, m5
%endif
    movq     rcx, m5
    test     rcx, rcx
%else
%if mmsize == 16
    pxor      m4, m4
    pcmpeqb   m5, m4
    pmovmskb ecx, m5
    cmp      ecx, (1<<mmsize)-1
%else
    packsswb  m5, m5
    movd     ecx, m5
    test     ecx, ecx
%endif
%endif
%endif ; cpuflag
    setne     al
%endmacro

%if HIGH_BIT_DEPTH
%macro QUANT_ONE_DC 4
%if cpuflag(sse4)
    mova        m0, [%1]
    ABSD        m1, m0
    paddd       m1, %3
    pmulld      m1, %2
    psrld       m1, 16
%else ; !sse4
    mova        m0, [%1]
    ABSD        m1, m0
    paddd       m1, %3
    mova        m2, m1
    psrlq       m2, 32
    pmuludq     m1, %2
    pmuludq     m2, %2
    psllq       m2, 32
    paddd       m1, m2
    psrld       m1, 16
%endif ; cpuflag
    PSIGND      m1, m0
    mova      [%1], m1
    ACCUM     por, 5, 1, %4
%endmacro

%macro QUANT_TWO_DC 4
%if cpuflag(sse4)
    mova        m0, [%1       ]
    mova        m1, [%1+mmsize]
    ABSD        m2, m0
    ABSD        m3, m1
    paddd       m2, %3
    paddd       m3, %3
    pmulld      m2, %2
    pmulld      m3, %2
    psrld       m2, 16
    psrld       m3, 16
    PSIGND      m2, m0
    PSIGND      m3, m1
    mova [%1       ], m2
    mova [%1+mmsize], m3
    ACCUM      por, 5, 2, %4
    por         m5, m3
%else ; !sse4
    QUANT_ONE_DC %1, %2, %3, %4
    QUANT_ONE_DC %1+mmsize, %2, %3, %4+mmsize
%endif ; cpuflag
%endmacro

%macro QUANT_ONE_AC_MMX 5
    mova        m0, [%1]
    mova        m2, [%2]
    ABSD        m1, m0
    mova        m4, m2
    paddd       m1, [%3]
    mova        m3, m1
    psrlq       m4, 32
    psrlq       m3, 32
    pmuludq     m1, m2
    pmuludq     m3, m4
    psllq       m3, 32
    paddd       m1, m3
    psrld       m1, 16
    PSIGND      m1, m0
    mova      [%1], m1
    ACCUM      por, %5, 1, %4
%endmacro

%macro QUANT_TWO_AC 5
%if cpuflag(sse4)
    mova        m0, [%1       ]
    mova        m1, [%1+mmsize]
    ABSD        m2, m0
    ABSD        m3, m1
    paddd       m2, [%3       ]
    paddd       m3, [%3+mmsize]
    pmulld      m2, [%2       ]
    pmulld      m3, [%2+mmsize]
    psrld       m2, 16
    psrld       m3, 16
    PSIGND      m2, m0
    PSIGND      m3, m1
    mova [%1       ], m2
    mova [%1+mmsize], m3
    ACCUM      por, %5, 2, %4
    por        m%5, m3
%else ; !sse4
    QUANT_ONE_AC_MMX %1, %2, %3, %4, %5
    QUANT_ONE_AC_MMX %1+mmsize, %2+mmsize, %3+mmsize, 1, %5
%endif ; cpuflag
%endmacro

;-----------------------------------------------------------------------------
; int quant_2x2( int32_t dct[M*N], int mf, int bias )
;-----------------------------------------------------------------------------
%macro QUANT_DC 2
cglobal quant_%1x%2_dc, 3,3,8
    QUANT_DC_START 6,7
%if %1*%2 <= mmsize/4
    QUANT_ONE_DC r0, m6, m7, 0
%else
%assign x 0
%rep %1*%2/(mmsize/2)
    QUANT_TWO_DC r0+x, m6, m7, x
%assign x x+mmsize*2
%endrep
%endif
    QUANT_END
    RET
%endmacro

;-----------------------------------------------------------------------------
; int quant_MxN( int32_t dct[M*N], uint32_t mf[M*N], uint32_t bias[M*N] )
;-----------------------------------------------------------------------------
%macro QUANT_AC 2
cglobal quant_%1x%2, 3,3,8
%assign x 0
%rep %1*%2/(mmsize/2)
    QUANT_TWO_AC r0+x, r1+x, r2+x, x, 5
%assign x x+mmsize*2
%endrep
    QUANT_END
    RET
%endmacro

%macro QUANT_4x4 2
    QUANT_TWO_AC r0+%1+mmsize*0, r1+mmsize*0, r2+mmsize*0, 0, %2
    QUANT_TWO_AC r0+%1+mmsize*2, r1+mmsize*2, r2+mmsize*2, 1, %2
%endmacro

%macro QUANT_4x4x4 0
cglobal quant_4x4x4, 3,3,8
    QUANT_4x4  0, 5
    QUANT_4x4 64, 6
    add       r0, 128
    packssdw  m5, m6
    QUANT_4x4  0, 6
    QUANT_4x4 64, 7
    packssdw  m6, m7
    packssdw  m5, m6  ; AAAA BBBB CCCC DDDD
    pxor      m4, m4
    pcmpeqd   m5, m4
    movmskps eax, m5
    xor      eax, 0xf
    RET
%endmacro

INIT_XMM sse2
QUANT_DC 2, 2
QUANT_DC 4, 4
QUANT_AC 4, 4
QUANT_AC 8, 8
QUANT_4x4x4

INIT_XMM ssse3
QUANT_DC 2, 2
QUANT_DC 4, 4
QUANT_AC 4, 4
QUANT_AC 8, 8
QUANT_4x4x4

INIT_XMM sse4
QUANT_DC 2, 2
QUANT_DC 4, 4
QUANT_AC 4, 4
QUANT_AC 8, 8
QUANT_4x4x4

INIT_YMM avx2
QUANT_DC 4, 4
QUANT_AC 4, 4
QUANT_AC 8, 8

INIT_YMM avx2
cglobal quant_4x4x4, 3,3,6
    QUANT_TWO_AC r0,    r1, r2, 0, 4
    QUANT_TWO_AC r0+64, r1, r2, 0, 5
    add       r0, 128
    packssdw  m4, m5
    QUANT_TWO_AC r0,    r1, r2, 0, 5
    QUANT_TWO_AC r0+64, r1, r2, 0, 1
    packssdw  m5, m1
    packssdw  m4, m5
    pxor      m3, m3
    pcmpeqd   m4, m3
    movmskps eax, m4
    mov      edx, eax
    shr      eax, 4
    and      eax, edx
    xor      eax, 0xf
    RET

%endif ; HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH == 0
%macro QUANT_ONE 5
;;; %1      (m64)       dct[y][x]
;;; %2      (m64/mmx)   mf[y][x] or mf[0][0] (as uint16_t)
;;; %3      (m64/mmx)   bias[y][x] or bias[0][0] (as uint16_t)
    mova       m1, %1   ; load dct coeffs
    ABSW       m0, m1, sign
    paddusw    m0, %3   ; round
    pmulhuw    m0, %2   ; divide
    PSIGNW     m0, m1   ; restore sign
    mova       %1, m0   ; store
    ACCUM     por, %5, 0, %4
%endmacro

%macro QUANT_TWO 8
    mova       m1, %1
    mova       m3, %2
    ABSW       m0, m1, sign
    ABSW       m2, m3, sign
    paddusw    m0, %5
    paddusw    m2, %6
    pmulhuw    m0, %3
    pmulhuw    m2, %4
    PSIGNW     m0, m1
    PSIGNW     m2, m3
    mova       %1, m0
    mova       %2, m2
    ACCUM     por, %8, 0, %7
    ACCUM     por, %8, 2, %7+mmsize
%endmacro

;-----------------------------------------------------------------------------
; void quant_4x4_dc( int16_t dct[16], int mf, int bias )
;-----------------------------------------------------------------------------
%macro QUANT_DC 2-3 0
cglobal %1, 1,1,%3
%if %2==1
    QUANT_DC_START 2,3
    QUANT_ONE [r0], m2, m3, 0, 5
%else
    QUANT_DC_START 4,6
%assign x 0
%rep %2/2
    QUANT_TWO [r0+x], [r0+x+mmsize], m4, m4, m6, m6, x, 5
%assign x x+mmsize*2
%endrep
%endif
    QUANT_END
    RET
%endmacro

;-----------------------------------------------------------------------------
; int quant_4x4( int16_t dct[16], uint16_t mf[16], uint16_t bias[16] )
;-----------------------------------------------------------------------------
%macro QUANT_AC 2
cglobal %1, 3,3
%if %2==1
    QUANT_ONE [r0], [r1], [r2], 0, 5
%else
%assign x 0
%rep %2/2
    QUANT_TWO [r0+x], [r0+x+mmsize], [r1+x], [r1+x+mmsize], [r2+x], [r2+x+mmsize], x, 5
%assign x x+mmsize*2
%endrep
%endif
    QUANT_END
    RET
%endmacro

%macro QUANT_4x4 2
%if UNIX64
    QUANT_TWO [r0+%1+mmsize*0], [r0+%1+mmsize*1], m8, m9, m10, m11, mmsize*0, %2
%else
    QUANT_TWO [r0+%1+mmsize*0], [r0+%1+mmsize*1], [r1+mmsize*0], [r1+mmsize*1], [r2+mmsize*0], [r2+mmsize*1], mmsize*0, %2
%if mmsize==8
    QUANT_TWO [r0+%1+mmsize*2], [r0+%1+mmsize*3], [r1+mmsize*2], [r1+mmsize*3], [r2+mmsize*2], [r2+mmsize*3], mmsize*2, %2
%endif
%endif
%endmacro

%macro QUANT_4x4x4 0
cglobal quant_4x4x4, 3,3,7
%if UNIX64
    mova      m8, [r1+mmsize*0]
    mova      m9, [r1+mmsize*1]
    mova     m10, [r2+mmsize*0]
    mova     m11, [r2+mmsize*1]
%endif
    QUANT_4x4  0, 4
    QUANT_4x4 32, 5
    packssdw  m4, m5
    QUANT_4x4 64, 5
    QUANT_4x4 96, 6
    packssdw  m5, m6
    packssdw  m4, m5  ; AAAA BBBB CCCC DDDD
    pxor      m3, m3
    pcmpeqd   m4, m3
    movmskps eax, m4
    xor      eax, 0xf
    RET
%endmacro

INIT_MMX mmx2
QUANT_DC quant_2x2_dc, 1
%if ARCH_X86_64 == 0 ; not needed because sse2 is faster
QUANT_DC quant_4x4_dc, 4
INIT_MMX mmx2
QUANT_AC quant_4x4, 4
QUANT_AC quant_8x8, 16
%endif

INIT_XMM sse2
QUANT_DC quant_4x4_dc, 2, 7
QUANT_AC quant_4x4, 2
QUANT_AC quant_8x8, 8
QUANT_4x4x4

INIT_XMM ssse3
QUANT_DC quant_4x4_dc, 2, 7
QUANT_AC quant_4x4, 2
QUANT_AC quant_8x8, 8
QUANT_4x4x4

INIT_MMX ssse3
QUANT_DC quant_2x2_dc, 1

INIT_XMM sse4
;Not faster on Conroe, so only used in SSE4 versions
QUANT_DC quant_4x4_dc, 2, 7
QUANT_AC quant_4x4, 2
QUANT_AC quant_8x8, 8

INIT_YMM avx2
QUANT_AC quant_4x4, 1
QUANT_AC quant_8x8, 4
QUANT_DC quant_4x4_dc, 1, 6

INIT_YMM avx2
cglobal quant_4x4x4, 3,3,6
    mova      m2, [r1]
    mova      m3, [r2]
    QUANT_ONE [r0+ 0], m2, m3, 0, 4
    QUANT_ONE [r0+32], m2, m3, 0, 5
    packssdw  m4, m5
    QUANT_ONE [r0+64], m2, m3, 0, 5
    QUANT_ONE [r0+96], m2, m3, 0, 1
    packssdw  m5, m1
    packssdw  m4, m5
    pxor      m3, m3
    pcmpeqd   m4, m3
    movmskps eax, m4
    mov      edx, eax
    shr      eax, 4
    and      eax, edx
    xor      eax, 0xf
    RET
%endif ; !HIGH_BIT_DEPTH



;=============================================================================
; dequant
;=============================================================================

%macro DEQUANT16_L 4
;;; %1      dct[y][x]
;;; %2,%3   dequant_mf[i_mf][y][x]
;;; m2      i_qbits
%if HIGH_BIT_DEPTH
    mova     m0, %1
    mova     m1, %4
    pmaddwd  m0, %2
    pmaddwd  m1, %3
    pslld    m0, xm2
    pslld    m1, xm2
    mova     %1, m0
    mova     %4, m1
%else
    mova     m0, %2
    packssdw m0, %3
%if mmsize==32
    vpermq   m0, m0, q3120
%endif
    pmullw   m0, %1
    psllw    m0, xm2
    mova     %1, m0
%endif
%endmacro

%macro DEQUANT32_R 4
;;; %1      dct[y][x]
;;; %2,%3   dequant_mf[i_mf][y][x]
;;; m2      -i_qbits
;;; m3      f
;;; m4      0
%if HIGH_BIT_DEPTH
    mova      m0, %1
    mova      m1, %4
    pmadcswd  m0, m0, %2, m3
    pmadcswd  m1, m1, %3, m3
    psrad     m0, xm2
    psrad     m1, xm2
    mova      %1, m0
    mova      %4, m1
%else
%if mmsize == 32
    pmovzxwd  m0, %1
    pmovzxwd  m1, %4
%else
    mova      m0, %1
    punpckhwd m1, m0, m4
    punpcklwd m0, m4
%endif
    pmadcswd  m0, m0, %2, m3
    pmadcswd  m1, m1, %3, m3
    psrad     m0, xm2
    psrad     m1, xm2
    packssdw  m0, m1
%if mmsize == 32
    vpermq    m0, m0, q3120
%endif
    mova      %1, m0
%endif
%endmacro

%macro DEQUANT_LOOP 3
%if 8*(%2-2*%3) > 0
    mov t0d, 8*(%2-2*%3)
%%loop:
    %1 [r0+(t0     )*SIZEOF_PIXEL], [r1+t0*2      ], [r1+t0*2+ 8*%3], [r0+(t0+ 4*%3)*SIZEOF_PIXEL]
    %1 [r0+(t0+8*%3)*SIZEOF_PIXEL], [r1+t0*2+16*%3], [r1+t0*2+24*%3], [r0+(t0+12*%3)*SIZEOF_PIXEL]
    sub t0d, 16*%3
    jge %%loop
    RET
%else
%if mmsize < 32
    %1 [r0+(8*%3)*SIZEOF_PIXEL], [r1+16*%3], [r1+24*%3], [r0+(12*%3)*SIZEOF_PIXEL]
%endif
    %1 [r0+(0   )*SIZEOF_PIXEL], [r1+0    ], [r1+ 8*%3], [r0+( 4*%3)*SIZEOF_PIXEL]
    RET
%endif
%endmacro

%macro DEQUANT16_FLAT 2-5
    mova   m0, %1
    psllw  m0, m4
%assign i %0-2
%rep %0-1
%if i
    mova   m %+ i, [r0+%2]
    pmullw m %+ i, m0
%else
    pmullw m0, [r0+%2]
%endif
    mova   [r0+%2], m %+ i
    %assign i i-1
    %rotate 1
%endrep
%endmacro

%if ARCH_X86_64
    DECLARE_REG_TMP 6,3,2
%else
    DECLARE_REG_TMP 2,0,1
%endif

%macro DEQUANT_START 2
    movifnidn t2d, r2m
    imul t0d, t2d, 0x2b
    shr  t0d, 8     ; i_qbits = i_qp / 6
    lea  t1d, [t0*5]
    sub  t2d, t0d
    sub  t2d, t1d   ; i_mf = i_qp % 6
    shl  t2d, %1
%if ARCH_X86_64
    add  r1, t2     ; dequant_mf[i_mf]
%else
    add  r1, r1mp   ; dequant_mf[i_mf]
    mov  r0, r0mp   ; dct
%endif
    sub  t0d, %2
    jl   .rshift32  ; negative qbits => rightshift
%endmacro

;-----------------------------------------------------------------------------
; void dequant_4x4( dctcoef dct[4][4], int dequant_mf[6][4][4], int i_qp )
;-----------------------------------------------------------------------------
%macro DEQUANT 3
cglobal dequant_%1x%1, 0,3,6
.skip_prologue:
    DEQUANT_START %2+2, %2

.lshift:
    movd xm2, t0d
    DEQUANT_LOOP DEQUANT16_L, %1*%1/4, %3

.rshift32:
    neg   t0d
    mova  m3, [pd_1]
    movd xm2, t0d
    pslld m3, xm2
    pxor  m4, m4
    psrld m3, 1
    DEQUANT_LOOP DEQUANT32_R, %1*%1/4, %3

%if HIGH_BIT_DEPTH == 0 && (notcpuflag(avx) || mmsize == 32)
cglobal dequant_%1x%1_flat16, 0,3
    movifnidn t2d, r2m
%if %1 == 8
    cmp  t2d, 12
    jl dequant_%1x%1 %+ SUFFIX %+ .skip_prologue
    sub  t2d, 12
%endif
    imul t0d, t2d, 0x2b
    shr  t0d, 8     ; i_qbits = i_qp / 6
    lea  t1d, [t0*5]
    sub  t2d, t0d
    sub  t2d, t1d   ; i_mf = i_qp % 6
    shl  t2d, %2
%if ARCH_X86_64
    lea  r1, [dequant%1_scale]
    add  r1, t2
%else
    lea  r1, [dequant%1_scale + t2]
%endif
    movifnidn r0, r0mp
    movd xm4, t0d
%if %1 == 4
%if mmsize == 8
    DEQUANT16_FLAT [r1], 0, 16
    DEQUANT16_FLAT [r1+8], 8, 24
%elif mmsize == 16
    DEQUANT16_FLAT [r1], 0, 16
%else
    vbroadcasti128 m0, [r1]
    psllw  m0, xm4
    pmullw m0, [r0]
    mova [r0], m0
%endif
%elif mmsize == 8
    DEQUANT16_FLAT [r1], 0, 8, 64, 72
    DEQUANT16_FLAT [r1+16], 16, 24, 48, 56
    DEQUANT16_FLAT [r1+16], 80, 88, 112, 120
    DEQUANT16_FLAT [r1+32], 32, 40, 96, 104
%elif mmsize == 16
    DEQUANT16_FLAT [r1], 0, 64
    DEQUANT16_FLAT [r1+16], 16, 48, 80, 112
    DEQUANT16_FLAT [r1+32], 32, 96
%else
    mova   m1, [r1+ 0]
    mova   m2, [r1+32]
    psllw  m1, xm4
    psllw  m2, xm4
    pmullw m0, m1, [r0+ 0]
    pmullw m3, m2, [r0+32]
    pmullw m4, m1, [r0+64]
    pmullw m5, m2, [r0+96]
    mova [r0+ 0], m0
    mova [r0+32], m3
    mova [r0+64], m4
    mova [r0+96], m5
%endif
    RET
%endif ; !HIGH_BIT_DEPTH && !AVX
%endmacro ; DEQUANT

%if HIGH_BIT_DEPTH
INIT_XMM sse2
DEQUANT 4, 4, 2
DEQUANT 8, 6, 2
INIT_XMM xop
DEQUANT 4, 4, 2
DEQUANT 8, 6, 2
INIT_YMM avx2
DEQUANT 4, 4, 4
DEQUANT 8, 6, 4
%else
%if ARCH_X86_64 == 0
INIT_MMX mmx
DEQUANT 4, 4, 1
DEQUANT 8, 6, 1
%endif
INIT_XMM sse2
DEQUANT 4, 4, 2
DEQUANT 8, 6, 2
INIT_XMM avx
DEQUANT 4, 4, 2
DEQUANT 8, 6, 2
INIT_XMM xop
DEQUANT 4, 4, 2
DEQUANT 8, 6, 2
INIT_YMM avx2
DEQUANT 4, 4, 4
DEQUANT 8, 6, 4
%endif

%macro DEQUANT_START_AVX512 1-2 0 ; shift, flat
%if %2 == 0
    movifnidn t2d, r2m
%endif
    imul t0d, t2d, 0x2b
    shr  t0d, 8     ; i_qbits = i_qp / 6
    lea  t1d, [t0*5]
    sub  t2d, t0d
    sub  t2d, t1d   ; i_mf = i_qp % 6
    shl  t2d, %1
%if %2
%if ARCH_X86_64
%define dmf r1+t2
    lea   r1, [dequant8_scale]
%else
%define dmf t2+dequant8_scale
%endif
%elif ARCH_X86_64
%define dmf r1+t2
%else
%define dmf r1
    add  r1, r1mp   ; dequant_mf[i_mf]
%endif
    movifnidn r0, r0mp
%endmacro

INIT_ZMM avx512
cglobal dequant_4x4, 0,3
    DEQUANT_START_AVX512 6
    mova          m0, [dmf]
%if HIGH_BIT_DEPTH
    pmaddwd       m0, [r0]
%endif
    sub          t0d, 4
    jl .rshift
%if HIGH_BIT_DEPTH
    vpbroadcastd  m1, t0d
    vpsllvd       m0, m1
    mova        [r0], m0
%else
    vpbroadcastw ym1, t0d
    vpmovsdw     ym0, m0
    pmullw       ym0, [r0]
    vpsllvw      ym0, ym1
    mova        [r0], ym0
%endif
    RET
.rshift:
%if HIGH_BIT_DEPTH == 0
    pmovzxwd      m1, [r0]
    pmaddwd       m0, m1
%endif
    mov          r1d, 1<<31
    shrx         r1d, r1d, t0d ; 1 << (-i_qbits-1)
    neg          t0d
    vpbroadcastd  m1, r1d
    vpbroadcastd  m2, t0d
    paddd         m0, m1
    vpsravd       m0, m2
%if HIGH_BIT_DEPTH
    mova        [r0], m0
%else
    vpmovsdw    [r0], m0
%endif
    RET

cglobal dequant_8x8, 0,3
    DEQUANT_START_AVX512 8
    mova          m0, [dmf+0*64]
    mova          m1, [dmf+1*64]
    mova          m2, [dmf+2*64]
    mova          m3, [dmf+3*64]
%if HIGH_BIT_DEPTH
    pmaddwd       m0, [r0+0*64]
    pmaddwd       m1, [r0+1*64]
    pmaddwd       m2, [r0+2*64]
    pmaddwd       m3, [r0+3*64]
%else
    mova          m6, [dequant_shuf_avx512]
%endif
    sub          t0d, 6
    jl .rshift
%if HIGH_BIT_DEPTH
    vpbroadcastd  m4, t0d
    vpsllvd       m0, m4
    vpsllvd       m1, m4
    vpsllvd       m2, m4
    vpsllvd       m3, m4
    jmp .end
.rshift:
%else
    vpbroadcastw  m4, t0d
    vpermt2w      m0, m6, m1
    vpermt2w      m2, m6, m3
    pmullw        m0, [r0]
    pmullw        m2, [r0+64]
    vpsllvw       m0, m4
    vpsllvw       m2, m4
    mova        [r0], m0
    mova     [r0+64], m2
    RET
.rshift:
    pmovzxwd      m4, [r0+0*32]
    pmovzxwd      m5, [r0+1*32]
    pmaddwd       m0, m4
    pmaddwd       m1, m5
    pmovzxwd      m4, [r0+2*32]
    pmovzxwd      m5, [r0+3*32]
    pmaddwd       m2, m4
    pmaddwd       m3, m5
%endif
    mov          r1d, 1<<31
    shrx         r1d, r1d, t0d ; 1 << (-i_qbits-1)
    neg          t0d
    vpbroadcastd  m4, r1d
    vpbroadcastd  m5, t0d
    paddd         m0, m4
    paddd         m1, m4
    vpsravd       m0, m5
    vpsravd       m1, m5
    paddd         m2, m4
    paddd         m3, m4
    vpsravd       m2, m5
    vpsravd       m3, m5
%if HIGH_BIT_DEPTH
.end:
    mova   [r0+0*64], m0
    mova   [r0+1*64], m1
    mova   [r0+2*64], m2
    mova   [r0+3*64], m3
%else
    vpermt2w      m0, m6, m1
    vpermt2w      m2, m6, m3
    mova        [r0], m0
    mova     [r0+64], m2
%endif
    RET

%if HIGH_BIT_DEPTH == 0
cglobal dequant_8x8_flat16, 0,3
    movifnidn    t2d, r2m
    cmp          t2d, 12
    jl dequant_8x8_avx512
    sub          t2d, 12
    DEQUANT_START_AVX512 6, 1
    vpbroadcastw  m0, t0d
    mova          m1, [dmf]
    vpsllvw       m1, m0
    pmullw        m0, m1, [r0]
    pmullw        m1, [r0+64]
    mova        [r0], m0
    mova     [r0+64], m1
    RET
%endif

%undef dmf

%if HAVE_MPEG2 && !HIGH_BIT_DEPTH
;-----------------------------------------------------------------------------
; void dequant_mpeg2_inter( dctcoef dct[64], int dequant_mf[64] )
;-----------------------------------------------------------------------------

; 32x32->32 low-dword multiply of two dword vectors: %1 *= mem %2, scratch %3,%4
%macro PMULLD_EMU 4
%if cpuflag(sse4)
    pmulld    %1, %2
%else
    mova      %4, %2
    pshufd    %3, %1, q2301
    pmuludq   %1, %4              ; even dword products
    pshufd    %4, %4, q2301
    pmuludq   %3, %4              ; odd dword products
    pshufd    %1, %1, q3120
    pshufd    %3, %3, q3120
    punpckldq %1, %3              ; interleave low dwords back in order
%endif
%endmacro

; process one register-width of coeffs (8 for xmm, 16 for ymm) at byte offset %1.
; m6 = pw_1, m7 = sum accumulator. Clip bounds taken from memory.
%macro DEQUANT_MPEG2_INTER_ROW 1
    mova       m0, [r0+%1]          ; dct
    pxor       m5, m5
    pcmpeqw    m5, m0               ; mask: -1 where dct==0
    psraw      m1, m0, 15           ; sign (0 / -1)
    ABSW       m0, m0, m2
    paddw      m0, m0
    por        m0, m6               ; t = |dct|*2 + 1   (unsigned, <= 4095)
%if mmsize == 32
    pmovzxwd   m2, xm0
    vextracti128 xm0, m0, 1
    pmovzxwd   m0, xm0
    PMULLD_EMU m2, [r1+%1*2   ], m8, m9
    PMULLD_EMU m0, [r1+%1*2+32], m8, m9
    psrld      m2, 6
    psrld      m0, 6
    packusdw   m2, m0
    vpermq     m2, m2, q3120
%else
    pxor       m3, m3
    mova       m2, m0
    punpcklwd  m2, m3               ; lo |t| dwords (zero-extended)
    punpckhwd  m0, m3               ; hi |t| dwords
    PMULLD_EMU m2, [r1+%1*2   ], m3, m4
    PMULLD_EMU m0, [r1+%1*2+16], m3, m4
    psrld      m2, 6
    psrld      m0, 6
%if cpuflag(sse4)
    packusdw   m2, m0
%else
    pslld      m2, 16
    psrad      m2, 16               ; sign-extend so packssdw keeps the value
    pslld      m0, 16
    psrad      m0, 16
    packssdw   m2, m0
%endif
%endif
    pxor       m2, m1               ; restore sign: (x ^ s) - s
    psubw      m2, m1
    pminsw     m2, [mpeg2_clip_max]
    pmaxsw     m2, [mpeg2_clip_min]
    pandn      m5, m2               ; keep result only where dct was nonzero
    mova       [r0+%1], m5
    pxor       m7, m5               ; sum ^= result
%endmacro

%macro DEQUANT_MPEG2_INTER 0
cglobal dequant_mpeg2_inter, 2,2,8+(mmsize/16)   ; xmm: m0-m7, ymm: m0-m9
    mova       m6, [pw_1]
    pxor       m7, m7
%assign i 0
%rep 128/mmsize
    DEQUANT_MPEG2_INTER_ROW i
%assign i i+mmsize
%endrep
    ; horizontal XOR of all word lanes in m7 down to its low word
%if mmsize == 32
    vextracti128 xm0, m7, 1
    pxor       xm7, xm0
%endif
    pshufd     xm0, xm7, q1032
    pxor       xm7, xm0
    pshuflw    xm0, xm7, q1032
    pxor       xm7, xm0
    pshuflw    xm0, xm7, q0001
    pxor       xm7, xm0             ; xm7 low word = XOR of all 64 results
    movd       eax, xm7
    not        eax
    and        eax, 1               ; 1 & ~sum
    xor        ax, [r0+63*2]
    mov        [r0+63*2], ax
    RET
%endmacro

INIT_XMM sse2
DEQUANT_MPEG2_INTER
INIT_XMM avx
DEQUANT_MPEG2_INTER
INIT_YMM avx2
DEQUANT_MPEG2_INTER

;-----------------------------------------------------------------------------
; void dequant_mpeg2_intra( dctcoef dct[64], int dequant_mf[64], int precision )
;-----------------------------------------------------------------------------

; process one register-width of coeffs (8 for xmm, 16 for ymm) at byte offset %1.
; m7 = sum accumulator. No odd bias, >>5, no zero check (intra dequants all coeffs).
%macro DEQUANT_MPEG2_INTRA_ROW 1
    mova       m0, [r0+%1]          ; dct
    psraw      m1, m0, 15           ; sign (0 / -1)
    ABSW       m0, m0, m2
%if mmsize == 32
    pmovzxwd   m2, xm0
    vextracti128 xm0, m0, 1
    pmovzxwd   m0, xm0
    PMULLD_EMU m2, [r1+%1*2   ], m8, m9
    PMULLD_EMU m0, [r1+%1*2+32], m8, m9
    psrld      m2, 5
    psrld      m0, 5
    packusdw   m2, m0
    vpermq     m2, m2, q3120
%else
    pxor       m3, m3
    mova       m2, m0
    punpcklwd  m2, m3               ; lo |dct| dwords (zero-extended)
    punpckhwd  m0, m3               ; hi |dct| dwords
    PMULLD_EMU m2, [r1+%1*2   ], m3, m4
    PMULLD_EMU m0, [r1+%1*2+16], m3, m4
    psrld      m2, 5
    psrld      m0, 5
%if cpuflag(sse4)
    packusdw   m2, m0
%else
    pslld      m2, 16
    psrad      m2, 16
    pslld      m0, 16
    psrad      m0, 16
    packssdw   m2, m0
%endif
%endif
    pxor       m2, m1               ; restore sign: (x ^ s) - s
    psubw      m2, m1
    pminsw     m2, [mpeg2_clip_max]
    pmaxsw     m2, [mpeg2_clip_min]
    mova       [r0+%1], m2
%if %1 == 0
    pand       m2, m6               ; exclude DC lane from the running sum
%endif
    pxor       m7, m2               ; sum ^= result
%endmacro

%macro DEQUANT_MPEG2_INTRA 0
cglobal dequant_mpeg2_intra, 3,3,8+(mmsize/16)
    ; DC: dct[0] <<= 3 - precision   (dct[0] is non-negative, fits 12 bits).
    ; Done with a SIMD variable shift to avoid a scalar shift-by-cl ABI hazard.
    neg        r2d
    add        r2d, 3             ; 3 - precision (shift count, 0..3)
    movd       xm0, r2d
    movd       xm5, [r0]          ; dct[0] in lane 0
    pslld      xm5, xm0           ; DC_shifted, held in xm5 across the loop
    mova       m6, [mpeg2_dc_summask]
    pxor       m7, m7
%assign i 0
%rep 128/mmsize
    DEQUANT_MPEG2_INTRA_ROW i
%assign i i+mmsize
%endrep
    ; m7 now holds XOR of AC[1..63] (DC lane excluded by the summask)
%if mmsize == 32
    vextracti128 xm0, m7, 1
    pxor       xm7, xm0
%endif
    pshufd     xm0, xm7, q1032
    pxor       xm7, xm0
    pshuflw    xm0, xm7, q1032
    pxor       xm7, xm0
    pshuflw    xm0, xm7, q0001
    pxor       xm7, xm0           ; xm7 lane 0 = XOR of AC[1..63]
    movd       r2d, xm5           ; DC_shifted
    mov        [r0], r2w          ; store into dct[0]
    movd       eax, xm7
    xor        eax, r2d           ; sum = DC_shifted XOR AC[1..63]
    not        eax
    and        eax, 1             ; 1 & ~sum
    xor        ax, [r0+63*2]
    mov        [r0+63*2], ax
    RET
%endmacro

INIT_XMM sse2
DEQUANT_MPEG2_INTRA
INIT_XMM avx
DEQUANT_MPEG2_INTRA
INIT_YMM avx2
DEQUANT_MPEG2_INTRA

; Signed int64 min helpers for the trellis DP's packed-key argmin on ISAs
; without native vpminsq. Legacy (non-VEX) pblendvb's blend mask is implicitly
; xmm0, so the SSE4.2 variant reserves xm0 as mask scratch.
%macro A2_MINQ 3 ; %1=acc %2=other %3=scratch (ymm idx): %1 = min(%1,%2) signed qword
    vpcmpgtq     ym%3, ym%1, ym%2     ; %1 > %2
    vpblendvb    ym%1, ym%1, ym%2, ym%3
%endmacro
%macro S4_MINQ 2 ; %1=acc %2=other(preserved): %1 = min(%1,%2) signed qword. clobbers xmm0
    movdqa       m0, m%1
    pcmpgtq      m0, m%2           ; xmm0 = (%1 > %2) qword mask
    pblendvb     m%1, m%2          ; %1 = %2 where %1>%2 (implicit xmm0 mask) -> min
%endmacro


;-----------------------------------------------------------------------------
; void trellis_rate_build_mpeg2( int64_t *dst, const uint16_t *bits, int64_t lambda )
; dst[run] = bits[run] * lambda for run 0..31 (4 groups of 8 qwords).
;-----------------------------------------------------------------------------
INIT_ZMM avx512
cglobal trellis_rate_build_mpeg2, 3,3,3
    vpbroadcastq m2, r2
    vpmovzxwq    m0, [r1+0]         ; bits[0..7]  -> int64
    vpmovzxwq    m1, [r1+16]        ; bits[8..15]
    vpmullq      m0, m0, m2
    vpmullq      m1, m1, m2
    mova         [r0+0],   m0       ; dst rows are ALIGNED_ARRAY_64 (each row 256B)
    mova         [r0+64],  m1
    vpmovzxwq    m0, [r1+32]        ; bits[16..23]
    vpmovzxwq    m1, [r1+48]        ; bits[24..31]
    vpmullq      m0, m0, m2
    vpmullq      m1, m1, m2
    mova         [r0+128], m0
    mova         [r0+192], m1
    RET

; AVX2 has no vpmullq, so emulate bits*lambda (bits<=16 bits) with two vpmuludq:
;   prod = bits*lambda_lo + (bits*lambda_hi << 32)   (exact; product < 2^56).
INIT_YMM avx2
cglobal trellis_rate_build_mpeg2, 3,3,5
    movq         xm2, r2
    vpbroadcastq m2, xm2           ; lambda (vpmuludq uses each qword's low 32 = lambda_lo)
    shr          r2, 32
    movq         xm3, r2
    vpbroadcastq m3, xm3           ; lambda_hi (in each qword's low 32)
%assign i 0
%rep 8
    vpmovzxwq    m0, [r1+i*8]      ; bits[4i..4i+3] -> int64 (4 lanes)
    vpmuludq     m1, m0, m3        ; bits * lambda_hi
    vpsllq       m1, m1, 32
    vpmuludq     m0, m0, m2        ; bits * lambda_lo
    vpaddq       m0, m0, m1        ; full product
    mova         [r0+i*32], m0
%assign i i+1
%endrep
    RET

; SSE4.2 version (2 int64 lanes). Same vpmuludq emulation of bits*lambda.
INIT_XMM sse42
cglobal trellis_rate_build_mpeg2, 3,3,4
    movq         xm2, r2
    punpcklqdq   m2, m2            ; lambda broadcast (low 32 of each = lambda_lo)
    shr          r2, 32
    movq         xm3, r2
    punpcklqdq   m3, m3            ; lambda_hi broadcast
%assign i 0
%rep 16
    pmovzxwq     m0, [r1+i*4]      ; bits[2i..2i+1] -> int64 (2 lanes)
    movdqa       m1, m0
    pmuludq      m1, m3            ; bits * lambda_hi
    psllq        m1, 32
    pmuludq      m0, m2            ; bits * lambda_lo
    paddq        m0, m1
    mova         [r0+i*16], m0
%assign i i+1
%endrep
    RET

;-----------------------------------------------------------------------------
; int trellis_setup_mpeg2( int *n, int *sgn, int64_t *dist_zero, int64_t *dist_n,
;                          int64_t *dist_nm1, const dctcoef *dct,
;                          const udctcoef *quant_mf, const udctcoef *quant_bias0,
;                          const int *dequant_mf, int intra )
; r0=n r1=sgn r2=dist_zero r3=dist_n r4=dist_nm1 r5=dct; stack: mf,bias0,dqmf,intra.
; Two passes over flat positions 0..63. Quant pass (always):
;   absc = |dct[f]|;  sgn = dct[f]<0 ? -1 : 1
;   q    = (bias0[f] + absc) * mf[f] >> 16
; Returns 0 with the dist arrays untouched when every q is zero (the common
; case for inter at mid/high QP); otherwise runs the dist pass and returns 1:
;   rn   = clip3( intra ? (q*dq)>>5 : ((2q+1)*dq)>>6, -2048, 2047 ) << 3   (0 if q==0)
;   rm   = same with (q-1)                                                 (used iff q>=2)
;   dist_zero = (i64)absc^2 << 8 ;  dist_n = (absc-rn)^2 << 8
;   dist_nm1  = q>=2 ? (absc-rm)^2 << 8 : dist_zero
; q is always >= 0 so the dequant rounding has no sign term; all 32-bit
; intermediates fit int32; squares widen to int64. Constants are broadcast from
; GPRs (no rodata) to avoid disturbing the section's alignment groups.
;-----------------------------------------------------------------------------
; dequant a level vector into ym7 = clip3( deq, -2048, 2047 ) << 3, branchlessly
; for both intra and inter. Identity: intra (q*dq)>>5 == (2q*dq)>>6, and inter is
; ((2q+1)*dq)>>6, so both are ((2*level + ym14)*dq)>>6 with ym14 = inter?1:0.
; Split so the (2*level+inter)*dq product (the only multiply) can be shared between
; q and q-1: dequant(q-1) = dequant(q)-2*dq pre-shift. TRELLIS_PROD -> ym6 (product),
; TRELLIS_FIN ym6 -> ym7 = clip3(product>>6)<<3.  dq in ym5, inter-bit in ym14.
%macro TRELLIS_PROD 1                  ; %1 = level -> ym15 = (2*level + inter)*dq
    vpaddd       ym15, %1, %1          ; 2*level
    vpaddd       ym15, ym15, ym14      ; 2*level + (inter ? 1 : 0)
    vpmulld      ym15, ym15, ym5       ; * dq
%endmacro
%macro TRELLIS_FIN 0                   ; ym15 (product) -> ym7 = clip3(product>>6)<<3
    vpsrad       ym7, ym15, 6          ; >> 6
    vpmaxsd      ym7, ym7, ym10        ; clip lo (-2048)
    vpminsd      ym7, ym7, ym11        ; clip hi (2047)
    vpslld       ym7, ym7, 3           ; << FDCT_SCALE
%endmacro

; Broadcast a 32-bit immediate into vector reg %1 (no rodata; uses eax as scratch,
; so call before loading pointers that may map onto rax). Picks the per-ISA idiom.
%macro BCASTI 2 ; %1 = dest vreg, %2 = imm32
    mov          eax, %2
%if cpuflag(avx512)
    vpbroadcastd m%1, eax             ; AVX-512 broadcasts straight from a GPR
%elif cpuflag(avx2)
    movd         xm%1, eax
    vpbroadcastd m%1, xm%1            ; AVX2 broadcast source must be xmm/mem
%else
    movd         xm%1, eax
    pshufd       m%1, m%1, 0
%endif
%endmacro

; m8 = (absc - r)^2 << 8 from ym1 (absc) and ym7 (r).  (compute only)
%macro TRELLIS_SQ 0
    vpsubd       ym8, ym1, ym7
    vpmovsxdq    m8, ym8
    vpmullq      m8, m8, m8
    vpsllq       m8, m8, 8
%endmacro
INIT_ZMM avx512
cglobal trellis_setup_mpeg2, 6,11,16
    ; broadcast constants first (uses eax as scratch) BEFORE loading pointers,
    ; since x86inc may map one of r6..r8 onto rax.
    BCASTI       10, -2048             ; clip lo
    BCASTI       11, 2047              ; clip hi
    BCASTI       12, 1                 ; +1 (for q-1)
    BCASTI       13, 2                 ; threshold 2 (q<2 test)
    mov          eax, r9m              ; intra (10th arg): 1 if intra, 0 if inter
    xor          eax, 1                ; -> inter bit (0 intra, 1 inter)
    vpbroadcastd m14, eax              ; ym14 = inter ? 1 : 0
    mov          r6, r6mp              ; quant_mf    (7th arg, on stack)
    mov          r7, r7mp              ; quant_bias0 (8th)
    mov          r8, r8mp              ; dequant_mf  (9th)
    ; quant pass: n, sgn, and an any-nonzero accumulator; the dist pass below
    ; is skipped entirely when every position quantizes to zero.
    vpxord       ym9, ym9, ym9         ; any-accumulator
    xor          r9d, r9d              ; f = group base
.qloop:
    vpmovsxwd    ym0, [r5+r9*2]        ; c = dct[f..f+7] (int16 -> int32)
    vpabsd       ym1, ym0              ; absc
    vpsrad       ym2, ym0, 31          ; c<0 ? -1 : 0
    vpord        ym2, ym2, ym12        ; sgn = that | 1
    movu         [r1+r9*4], ym2        ; sgn[f..]
    vpmovzxwd    ym3, [r7+r9*2]        ; bias0
    vpmovzxwd    ym4, [r6+r9*2]        ; mf
    vpaddd       ym3, ym3, ym1         ; bias0 + absc
    vpmulld      ym3, ym3, ym4         ; * mf
    vpsrld       ym3, ym3, 16          ; q
    movu         [r0+r9*4], ym3        ; n[f..] = q
    vpord        ym9, ym9, ym3         ; any |= q
    add          r9d, 8
    cmp          r9d, 64
    jl .qloop
    xor          eax, eax
    vptestmd     k2, ym9, ym9          ; k2 = per-lane (any != 0)
    kortestb     k2, k2
    jz .end                            ; all-zero: return 0, dist arrays untouched
    mov          eax, 1
    xor          r9d, r9d
.dloop:
    vpmovsxwd    ym0, [r5+r9*2]        ; c (reload)
    vpabsd       ym1, ym0              ; absc
    movu         ym3, [r0+r9*4]        ; q (reload from n[])
    movu         ym5, [r8+r9*4]        ; dq = dequant_mf[f..]
    ; dist_zero = absc^2 << 8  (kept in m6 for the dist_nm1 select)
    vpmovsxdq    m6, ym1
    vpmullq      m6, m6, m6
    vpsllq       m6, m6, 8
    movu         [r2+r9*8], m6
    ; dist_n = (absc - rn)^2 << 8.  dequant(0)==0 by definition; intra yields 0 at
    ; q==0 but inter's +1 oddification does not, so force rn=0 where q==0 (a no-op
    ; for intra, since rn is already 0 there).
    TRELLIS_PROD ym3                   ; ym15 = (2q+inter)*dq  (shared with q-1 below)
    TRELLIS_FIN                        ; ym7 = rn
    vptestmd     k2, ym3, ym3          ; k2 = (q != 0)
    vmovdqa32    ym7{k2}{z}, ym7       ; zero rn where q==0
    TRELLIS_SQ                         ; m8 = dist_n
    movu         [r3+r9*8], m8
    ; dist_nm1 = q>=2 ? (absc - rm)^2<<8 : dist_zero   (q-1 >= 1 so no q==0 guard).
    ; dequant(q-1) = dequant(q) - 2*dq pre-shift, so reuse the product in ym15.
    vpaddd       ym9, ym5, ym5         ; 2*dq
    vpsubd       ym15, ym15, ym9       ; product for q-1
    TRELLIS_FIN
    TRELLIS_SQ                         ; m8 = (q-1) distortion
    vpcmpd       k1, ym3, ym13, 1      ; k1 = (q < 2)
    vmovdqa64    m8{k1}, m6            ; where q<2, use dist_zero
    movu         [r4+r9*8], m8
    add          r9d, 8
    cmp          r9d, 64
    jl .dloop
.end:
    RET

; AVX2 setup. Same math; AVX2 lacks mask regs and vpmullq. The squared diffs fit
; int32 (|d|<=16383 => d^2 < 2^31), so all distortion selection is done in int32
; (8-wide) and only the final result is widened 8 int32 -> 8 int64 (two halves)
; and shifted <<8 for the int64 outputs. Selects use vpblendvb with compare masks.
; ym10=clip lo, ym11=clip hi, ym12=+1, ym13=2, ym14=inter bit.
; Split as AVX-512: PROD computes the (only) multiply into ym15 so q and q-1 can
; share it (dequant(q-1)=dequant(q)-2*dq pre-shift); FIN does >>6/clip/<<3 -> ym7.
; Shared AVX2/SSE4.2 setup (the "narrow" ISAs: no mask regs, no cheap vpmullq, so
; squares are computed in int32 and widened to int64<<8 by the per-ISA WIDEN macro).
; Written with non-v mnemonics + 3-operand forms so x86inc emits SSE under INIT_XMM
; and AVX under INIT_YMM. PROD does the one multiply into m15 (shared by q and q-1
; via dequant(q-1)=dequant(q)-2*dq pre-shift); FIN does >>6/clip/<<3 -> m7.
%macro TRELLIS_PROD_N 1 ; %1=level -> m15 = (2*level+inter)*dq
    paddd        m15, %1, %1
    paddd        m15, m14
    pmulld       m15, m5
%endmacro
%macro TRELLIS_FIN_N 0  ; m15 -> m7 = clip3(m15>>6)<<3
    psrad        m7, m15, 6
    pmaxsd       m7, m10
    pminsd       m7, m11
    pslld        m7, 3
%endmacro
; widen 8 int32 squares in ym%2 to 8 int64<<8 (two 128-bit halves) and store at [%1].
%macro TRELLIS_WIDEN_STORE_A2 2
    vpmovsxdq    m6,  xm%2
    vextracti128 xm%2, ym%2, 1
    vpmovsxdq    m%2, xm%2
    vpsllq       m6, m6, 8
    vpsllq       m%2, m%2, 8
    movu         [%1],    m6
    movu         [%1+32], m%2
%endmacro
; widen 4 int32 squares in m%2 to 4 int64<<8 (low-2 then high-2) and store at [%1].
%macro TRELLIS_WIDEN_STORE_S4 2
    pmovsxdq     m6, xm%2
    psllq        m6, 8
    movu         [%1], m6
    punpckhqdq   m%2, m%2
    pmovsxdq     m%2, xm%2
    psllq        m%2, 8
    movu         [%1+16], m%2
%endmacro
; One setup loop body for both narrow ISAs. %1 = the WIDEN_STORE macro name. The
; only ISA divergence is the q<2 select (vpblendvb on AVX2 vs and/andn/or on SSE4.2,
; whose legacy pblendvb mask must be xmm0). Lane count is implicit in mmsize.
%macro TRELLIS_SETUP_NARROW 1
    BCASTI       10, -2048         ; clip lo
    BCASTI       11, 2047          ; clip hi
    BCASTI       12, 1             ; +1
    BCASTI       13, 2             ; 2
    mov          eax, r9m
    xor          eax, 1            ; inter bit
    BCASTI       14, eax           ; (eax already holds the value; BCASTI re-movs it)
    mov          r6, r6mp
    mov          r7, r7mp
    mov          r8, r8mp
    ; quant pass: n, sgn, any-accumulator; the dist pass is skipped when all-zero.
    pxor         m9, m9
    xor          r9d, r9d
%%qloop:
    pmovsxwd     m0, [r5+r9*2]     ; c
    pabsd        m1, m0            ; absc
    psrad        m2, m0, 31
    por          m2, m12           ; sgn
    movu         [r1+r9*4], m2
    pmovzxwd     m3, [r7+r9*2]     ; bias0
    pmovzxwd     m4, [r6+r9*2]     ; mf
    paddd        m3, m1
    pmulld       m3, m4
    psrld        m3, 16            ; q
    movu         [r0+r9*4], m3
    por          m9, m3            ; any |= q
    add          r9d, mmsize/4
    cmp          r9d, 64
    jl %%qloop
    xor          eax, eax
    ptest        m9, m9
    jz %%end                       ; all-zero: return 0, dist arrays untouched
    mov          eax, 1
    xor          r9d, r9d
%%dloop:
    pmovsxwd     m0, [r5+r9*2]     ; c (reload)
    pabsd        m1, m0            ; absc
    movu         m3, [r0+r9*4]     ; q (reload from n[])
    movu         m5, [r8+r9*4]     ; dq
    ; dist_zero: absc^2 (int32) kept in m0 for the q<2 select; m8 copy for the store
    pmulld       m0, m1, m1        ; absc^2 (m1=absc preserved)
    movdqa       m8, m0
    %1           r2+r9*8, 8
    ; dist_n = (absc - rn)^2, rn forced 0 where q==0 (no-op for intra)
    TRELLIS_PROD_N m3             ; m15 = (2q+inter)*dq  (shared with q-1 below)
    TRELLIS_FIN_N
    pxor         m4, m4
    pcmpeqd      m4, m3            ; q==0 mask
    pandn        m4, m7            ; rn where q!=0 (~m4 & m7)
    movdqa       m7, m4            ; keep rn in m7 (reused for dist_nm1)
    psubd        m8, m1, m7        ; absc - rn
    pmulld       m8, m8            ; (absc-rn)^2 int32
    %1           r3+r9*8, 8
    ; dist_nm1 = q<2 ? absc^2 : (absc-rm)^2. dequant(q-1)=dequant(q)-2*dq pre-shift.
    paddd        m9, m5, m5        ; 2*dq
    psubd        m15, m9           ; product for q-1
    TRELLIS_FIN_N
    psubd        m8, m1, m7        ; absc - rm
    pmulld       m8, m8            ; (absc-rm)^2 int32
%if cpuflag(avx2)
    vpcmpgtd     m4, m13, m3       ; q < 2
    vpblendvb    m8, m8, m0, m4    ; where q<2 take absc^2 (m0)
    %1           r4+r9*8, 8
%else
    movdqa       m4, m13
    pcmpgtd      m4, m3            ; (2 > q) = (q < 2) mask
    pand         m0, m4            ; absc^2 where q<2  (no pblendvb: mask must be xmm0)
    pandn        m4, m8            ; (absc-rm)^2 where q>=2
    por          m4, m0            ; selected dist_nm1 (int32) in m4
    %1           r4+r9*8, 4
%endif
    add          r9d, mmsize/4     ; 8 lanes (avx2) or 4 (sse)
    cmp          r9d, 64
    jl %%dloop
%%end:
    RET
%endmacro

INIT_YMM avx2
cglobal trellis_setup_mpeg2, 6,11,16
    TRELLIS_SETUP_NARROW TRELLIS_WIDEN_STORE_A2

INIT_XMM sse42
cglobal trellis_setup_mpeg2, 6,11,16
    TRELLIS_SETUP_NARROW TRELLIS_WIDEN_STORE_S4

;-----------------------------------------------------------------------------
; int trellis_dp_mpeg2( const x264_trellis_dp_ctx_t *t )
; Whole-DP kernel: the predecessor DP over the candidate list with the near-
; window argmin inlined, then the terminal scan. Uniting the DP with the argmin
; removes per-position call overhead and hoists the argmin's vector constants
; once per block. One shared scalar skeleton, instantiated for SSE4.2/AVX2/
; AVX-512 with per-ISA window-argmin bodies. Semantics and tie-breaks must
; match the C reference trellis_dp_mpeg2 (common/quant.c) exactly. Field
; offsets below are ABI with x264_trellis_dp_ctx_t (static-asserted in
; common/quant.c).
;-----------------------------------------------------------------------------
%define t_n         0
%define t_dist_zero 8
%define t_dist_n    16
%define t_dist_nm1  24
%define t_scan      32
%define t_list      40
%define t_cnt       48
%define t_first     52
%define t_inter     56
%define t_lambda    64
%define t_esc_lam   72
%define t_rate_lam  80
%define t_max_lev   88
%define t_esc_row   96
%define t_back      104
%define t_lev       112

; stack frame: int64 cost[64] then scalar slots
%define v_first     rsp+512
%define v_maxlev    rsp+516
%define v_cnt       rsp+520
%define v_nf        rsp+524
%define v_plo       rsp+528
%define v_width     rsp+532
%define v_inter     rsp+536
%define v_esclam    rsp+544
%define v_lam2      rsp+552
%define v_eob       rsp+560
%define v_inf       rsp+568
%define v_gain0     rsp+576
%define v_gain1     rsp+584
%define v_rl0       rsp+592
%define v_rl1       rsp+600
%define v_gain      rsp+608
%define v_rl        rsp+616
%define v_rllo      rsp+624
%define v_costlo    rsp+632

; Per-block constant setup: INF-fill the cost array (r6 = INF on entry) and
; hoist the window-argmin's vector constants. m5=INF_CAP m7=index advance
; m8=max-key m13=index base; avx512 also m4=reverse-permute.
%macro TRELLIS_DP_CONSTS 0
%if cpuflag(avx512)
    vpbroadcastq m1, r6
%elif cpuflag(avx2)
    movq         xm1, r6
    vpbroadcastq m1, xm1
%else
    movq         xm1, r6
    punpcklqdq   m1, m1
%endif
%assign %%i 0
%rep 512/mmsize
    movu         [rsp+%%i*mmsize], m1
%assign %%i %%i+1
%endrep
    mova         m13, [trellis_idx8_q] ; index ramp: low mmsize/8 qwords
%if cpuflag(avx512)
    mova         m4, [trellis_rev8_q]
%endif
    mov          r6, 1
    shl          r6, 56                ; INF_CAP
%if cpuflag(avx512)
    vpbroadcastq m5, r6
    vpternlogd   m8, m8, m8, 0xff
    vpsrlq       m8, m8, 1             ; max key
%elif cpuflag(avx2)
    movq         xm5, r6
    vpbroadcastq m5, xm5
    vpcmpeqd     m8, m8, m8
    vpsrlq       m8, m8, 1
%else
    movq         xm5, r6
    punpcklqdq   m5, m5
    pcmpeqd      m8, m8
    psrlq        m8, 1
%endif
    mov          r6d, mmsize/8
%if cpuflag(avx512)
    vpbroadcastq m7, r6                ; per-group index advance
%elif cpuflag(avx2)
    movq         xm7, r6
    vpbroadcastq m7, xm7
%else
    movq         xm7, r6
    punpcklqdq   m7, m7
%endif
%endmacro

; One candidate level's three predecessor merges (NONE edge, near-window
; argmin, far running-min), %1 = cand (0: L=nf, 1: L=nf-1). Persistent regs:
; r0=ctx r1=list r2=scan r3=n r4=li r7=s r8=min_far r9=min_far_p r10=far_li
; r12=best_keep r13=best_meta(=prev*2+cand). Scratch: r5 r6 r11 r14; m2 holds
; the per-candidate gain broadcast. The near-window argmin uses the packed-key
; method: key = min(sc,INF_CAP)*64 | (p-p_lo); one signed-qword min resolves
; the minimum and the lowest-p tie-break; the winner's true score is
; recomputed scalar and merged with strict < (so an all-INF window can never
; beat the always-finite NONE edge).
%macro DP_CAND 1
%if %1 == 1
    mov          r5d, [v_nf]
    cmp          r5d, 2
    jl           %%skip            ; L = nf-1 < 1: no such candidate
    dec          r5d               ; L
    mov          r6, [v_gain1]
    mov          r14, [v_rl1]
%else
    mov          r5d, [v_nf]       ; L = nf
    mov          r6, [v_gain0]
    mov          r14, [v_rl0]
%endif
    mov          [v_gain], r6
    mov          [v_rl], r14
    ; --- NONE edge: run = s-first; rate = rl[run] (esc past the cap), except
    ;     the inter first-coefficient magnitude-1 special case (2 bits) ---
    mov          r6d, r7d
    sub          r6d, [v_first]    ; run
    cmp          r6d, 31
    jg           %%rate_esc
    mov          r11, [r14+r6*8]   ; rl[run]
    jmp          %%rate_ok
%%rate_esc:
    mov          r11, [v_esclam]
%%rate_ok:
    cmp          dword [v_inter], 0
    je           %%nospecial
    test         r6d, r6d
    jnz          %%nospecial
    cmp          r5d, 1
    jne          %%nospecial
    mov          r11, [v_lam2]     ; table B.14 special case + sign
%%nospecial:
    add          r11, [v_gain]
    mov          r6d, [v_first]
    dec          r6d               ; NONE
    lea          r6d, [r6d*2+%1]   ; meta
    cmp          r11, r12
    cmovl        r12, r11
    cmovl        r13d, r6d
    ; --- near-window argmin: min over p in [p_lo,s) of cost[p]+gain+rl[s-1-p] ---
    mov          r5d, [v_width]
    test         r5d, r5d
    jle          %%far             ; empty window (s == first)
    mov          r6d, r7d
    dec          r6d
    sub          r6d, [v_plo]
    mov          r14, [v_rl]
    lea          r14, [r14+r6*8]   ; &rl[s-1-p_lo]
    mov          [v_rllo], r14
    mov          r6, [v_costlo]    ; walking cost ptr
    sub          r14, mmsize-8     ; walking rl group ptr (low-lane address)
%if cpuflag(avx512)
    vpbroadcastq m2, [v_gain]
    mova         m3, m13           ; index vector = 0..7
    mova         m0, m8            ; running key-min = max key
%%aloop:
    cmp          r5d, 8
    jl           %%atail
    vmovdqu64    m1, [r6]
    vmovdqu64    m6, [r14]
    vpermq       m6, m4, m6        ; reverse -> lane i = rl[s-1-p]
    vpaddq       m1, m1, m2
    vpaddq       m1, m1, m6
    vpminsq      m1, m1, m5        ; cap so *64 can't overflow
    vpsllq       m1, m1, 6
    vporq        m1, m1, m3        ; key = sc*64 | (p-p_lo)
    vpminsq      m0, m0, m1
    vpaddq       m3, m3, m7
    add          r6, 64
    sub          r14, 64
    sub          r5d, 8
    jmp          %%aloop
%%atail:
    test         r5d, r5d
    jz           %%areduce
    mov          r11d, 1
    shlx         r11d, r11d, r5d
    dec          r11d              ; (1<<remaining)-1: cost low-lane mask
    kmovb        k1, r11d
    mov          r11d, 8
    sub          r11d, r5d
    mov          r5d, 0xff
    shlx         r5d, r5d, r11d    ; rl mask: active in HIGH lanes pre-reverse
    kmovb        k3, r5d
    vmovdqu64    m1{k1}{z}, [r6]
    vmovdqu64    m6{k3}{z}, [r14]
    vpermq       m6, m4, m6
    vpaddq       m1, m1, m2
    vpaddq       m1, m1, m6
    vpminsq      m1, m1, m5
    vpsllq       m1, m1, 6
    vporq        m1, m1, m3
    knotb        k2, k1
    vmovdqa64    m1{k2}, m8        ; inactive lanes -> max key
    vpminsq      m0, m0, m1
%%areduce:
    vextracti64x4 ym1, m0, 1
    vpminsq      ym0, ym0, ym1
    vextracti128 xm1, ym0, 1
    vpminsq      xm0, xm0, xm1
    vpshufd      xm1, xm0, q1032
    vpminsq      xm0, xm0, xm1
    vmovq        r14, xm0          ; winning packed key
%elif cpuflag(avx2)
    vpbroadcastq m2, [v_gain]
    mova         m3, m13           ; index vector = 0..3
    mova         m0, m8            ; running key-min = max key
%%aloop:
    cmp          r5d, 4
    jl           %%atail
    vmovdqu      m1, [r6]
    vmovdqu      m6, [r14]
    vpermq       m6, m6, 0x1b      ; reverse 4 qwords
    vpaddq       m1, m1, m2
    vpaddq       m1, m1, m6
    A2_MINQ      1, 5, 9           ; cap at INF_CAP
    vpsllq       m1, m1, 6
    vpor         m1, m1, m3        ; key = sc*64 | (p-p_lo)
    A2_MINQ      0, 1, 9
    vpaddq       m3, m3, m7
    add          r6, 32
    sub          r14, 32
    sub          r5d, 4
    jmp          %%aloop
%%atail:
    test         r5d, r5d
    jz           %%areduce
    movq         xm10, r5
    vpbroadcastq m10, xm10
    vpcmpgtq     m10, m10, m13   ; low-rem-active:  lane < rem
    vpermq       m11, m10, 0x1b  ; high-rem-active: low reversed
    vpmaskmovq   m1, m10, [r6]
    vpmaskmovq   m6, m11, [r14]
    vpermq       m6, m6, 0x1b
    vpaddq       m1, m1, m2
    vpaddq       m1, m1, m6
    A2_MINQ      1, 5, 9
    vpsllq       m1, m1, 6
    vpor         m1, m1, m3
    vpblendvb    m1, m8, m1, m10   ; inactive lanes -> max key
    A2_MINQ      0, 1, 9
%%areduce:
    vextracti128 xm1, m0, 1
    A2_MINQ      0, 1, 9
    vpshufd      xm1, xm0, q1032
    vpcmpgtq     xm9, xm0, xm1
    vpblendvb    xm0, xm0, xm1, xm9
    vmovq        r14, xm0          ; winning packed key
%else ; SSE4.2
    movq         xm2, [v_gain]
    punpcklqdq   m2, m2
    mova         m3, m13           ; index vector = 0..1
    mova         m9, m8            ; running key-min (m0 reserved: pblendvb mask)
%%aloop:
    cmp          r5d, 2
    jl           %%atail
    movdqu       m1, [r6]
    movdqu       m6, [r14]
    pshufd       m6, m6, q1032     ; swap the 2 qwords
    paddq        m1, m2
    paddq        m1, m6
    S4_MINQ      1, 5              ; cap at INF_CAP
    psllq        m1, 6
    por          m1, m3            ; key = sc*64 | (p-p_lo)
    S4_MINQ      9, 1
    paddq        m3, m7
    add          r6, 16
    sub          r14, 16
    sub          r5d, 2
    jmp          %%aloop
%%atail:
    pshufd       m1, m9, q1032
    S4_MINQ      9, 1
    movq         r14, xm9          ; winning packed key from full pairs
    test         r5d, r5d
    jz           %%areduce
    ; single remaining element (j = width-1, the HIGHEST p: strict < keeps
    ; the lower-p vector winner on ties, matching the C reference)
    mov          r5d, [v_width]
    dec          r5d               ; j
    mov          r11, [v_costlo]
    mov          r6, [r11+r5*8]    ; cost[p_lo+j]
    add          r6, [v_gain]
    mov          r11, r5
    neg          r11
    shl          r11, 3
    add          r11, [v_rllo]
    add          r6, [r11]         ; + rl[s-1-p_lo-j] -> sc
    mov          r11, 1
    shl          r11, 56
    cmp          r6, r11
    cmovg        r6, r11           ; min(sc, INF_CAP)
    shl          r6, 6
    or           r6, r5            ; key = sc*64 | j
    cmp          r6, r14
    cmovl        r14, r6
%%areduce:
%endif
    ; shared: idx -> true score -> merge (strict <)
    mov          r5d, r14d
    and          r5d, 63           ; idx = p - p_lo
    mov          r6, [v_costlo]
    mov          r6, [r6+r5*8]     ; cost[p]
    add          r6, [v_gain]
    mov          r14, r5
    neg          r14
    mov          r11, [v_rllo]
    add          r6, [r11+r14*8]   ; + rl[s-1-p]: true score
    add          r5d, [v_plo]      ; p
    lea          r5d, [r5d*2+%1]   ; meta
    cmp          r6, r12
    cmovl        r12, r6
    cmovl        r13d, r5d
%%far:
    ; --- far predecessors: run > cap, escape-coded at constant bits ---
    cmp          r8, [v_inf]
    jge          %%skip
    mov          r11, r8
    add          r11, [v_gain]
    add          r11, [v_esclam]
    lea          r5d, [r9d*2+%1]
    cmp          r11, r12
    cmovl        r12, r11
    cmovl        r13d, r5d
%%skip:
%endmacro

; The shared scalar skeleton (identical for every tier; only DP_CAND's window
; section differs by ISA).
%macro TRELLIS_DP 0
cglobal trellis_dp_mpeg2, 1,15,16, 0-640
    mov          r1, [r0+t_list]
    mov          r2, [r0+t_scan]
    mov          r3, [r0+t_n]
    mov          r5d, [r0+t_first]
    mov          [v_first], r5d
    mov          r5d, [r0+t_max_lev]
    mov          [v_maxlev], r5d
    mov          r5d, [r0+t_cnt]
    mov          [v_cnt], r5d
    mov          r5d, [r0+t_inter]
    mov          [v_inter], r5d
    mov          r6, [r0+t_esc_lam]
    mov          [v_esclam], r6
    mov          r6, [r0+t_lambda]
    add          r6, r6
    mov          [v_lam2], r6      ; 2*lambda
    xor          r11d, r11d
    test         r5d, r5d
    cmovnz       r11, r6
    mov          [v_eob], r11      ; EOB = inter ? 2*lambda : 0
    mov          r6, 1
    shl          r6, 62
    mov          [v_inf], r6       ; INF
    mov          r8, r6            ; min_far = INF
    mov          r9d, [v_first]
    dec          r9d               ; min_far_p = NONE
    xor          r10d, r10d        ; far_li = 0
    xor          r4d, r4d          ; li = 0
    ; cost[0..63] = INF (only [first,64) is read; slot 0 is harmless), then
    ; the hoisted vector constants (r6 = INF here, clobbered after)
    TRELLIS_DP_CONSTS
.mainloop:
    cmp          r4d, [v_cnt]
    jge          .terminal
    movzx        r7d, byte [r1+r4] ; s = list[li]
    ; roll predecessors past the run cap into the far running-min:
    ; list[far_li] < s-1-31 while far_li < li
    mov          r14d, r7d
    sub          r14d, 32
.farloop:
    cmp          r10d, r4d
    jge          .fardone
    movzx        r5d, byte [r1+r10]
    cmp          r5d, r14d
    jge          .fardone
    mov          r6, [rsp+r5*8]    ; cost[p]
    cmp          r6, r8
    cmovl        r8, r6
    cmovl        r9d, r5d
    inc          r10d
    jmp          .farloop
.fardone:
    movzx        r5d, byte [r2+r7] ; f = scan[s]
    mov          r6d, [r3+r5*4]    ; nf = n[f]
    mov          [v_nf], r6d
    ; candidate gains: dist_{n,nm1}[f] - dist_zero[f]
    mov          r11, [r0+t_dist_zero]
    mov          r11, [r11+r5*8]
    mov          r14, [r0+t_dist_n]
    mov          r14, [r14+r5*8]
    sub          r14, r11
    mov          [v_gain0], r14
    mov          r14, [r0+t_dist_nm1]
    mov          r14, [r14+r5*8]
    sub          r14, r11
    mov          [v_gain1], r14
    ; rate rows: row(L) = L <= max_lev ? rate_lam + L*256 : esc_row
    mov          r11, [r0+t_rate_lam]
    mov          r14, [r0+t_esc_row]
    mov          r5d, r6d
    shl          r5d, 8
    add          r5, r11
    cmp          r6d, [v_maxlev]
    cmovg        r5, r14
    mov          [v_rl0], r5
    dec          r6d               ; L1 = nf-1 (row unused when nf < 2)
    mov          r5d, r6d
    shl          r5d, 8
    add          r5, r11
    cmp          r6d, [v_maxlev]
    cmovg        r5, r14
    mov          [v_rl1], r5
    ; p_lo = max(first, s-1-31), width, &cost[p_lo]
    mov          r5d, r7d
    sub          r5d, 32
    mov          r14d, [v_first]
    cmp          r5d, r14d
    cmovl        r5d, r14d
    mov          [v_plo], r5d
    mov          r14d, r7d
    sub          r14d, r5d
    mov          [v_width], r14d
    lea          r5, [rsp+r5*8]
    mov          [v_costlo], r5
    ; best-so-far: (INF, NONE, cand 0); the cand-0 NONE edge always beats it
    mov          r12, [v_inf]
    mov          r13d, [v_first]
    dec          r13d
    add          r13d, r13d
    DP_CAND      0
    DP_CAND      1
    ; commit state s: cost, back = meta>>1, lev = nf - (meta&1)
    mov          [rsp+r7*8], r12
    mov          r6d, r13d
    sar          r6d, 1
    mov          r14, [r0+t_back]
    mov          [r14+r7*4], r6d
    mov          r5d, [v_nf]
    mov          r6d, r13d
    and          r6d, 1
    sub          r5d, r6d
    mov          r14, [r0+t_lev]
    mov          [r14+r7*4], r5d
    inc          r4d
    jmp          .mainloop
.terminal:
    ; all-drop path has gain 0; EOB paid only when a coef is kept (inter)
    xor          r12d, r12d        ; best = 0
    mov          r13d, [v_first]
    dec          r13d              ; best_last = NONE
    xor          r4d, r4d
.tloop:
    cmp          r4d, [v_cnt]
    jge          .tdone
    movzx        r7d, byte [r1+r4]
    mov          r6, [rsp+r7*8]
    add          r6, [v_eob]
    cmp          r6, r12
    cmovl        r12, r6
    cmovl        r13d, r7d
    inc          r4d
    jmp          .tloop
.tdone:
    mov          eax, r13d
    RET
%endmacro

INIT_ZMM avx512
TRELLIS_DP
INIT_YMM avx2
TRELLIS_DP
INIT_XMM sse42
TRELLIS_DP

;-----------------------------------------------------------------------------
; int trellis_list_mpeg2( uint8_t *list, const int *n, const uint8_t *scan )
; Scan-order list of the positions s (0..63) with n[scan[s]] != 0, returning
; the count: flat nonzero mask over n[] -> bytes -> permuted into scan order
; by the zigzag table -> compress the byte iota. Entries beyond the returned
; count are zero-filled (callers must treat them as undefined). Replaces a
; 64-iteration scalar gather loop in x264_quant_8x8_trellis_mpeg2.
;-----------------------------------------------------------------------------
INIT_ZMM avx512icl
cglobal trellis_list_mpeg2, 3,4,3
    vmovdqu32    m0, [r1]
    vptestmd     k1, m0, m0            ; n[0..15]  != 0
    vmovdqu32    m0, [r1+64]
    vptestmd     k2, m0, m0            ; n[16..31] != 0
    vmovdqu32    m0, [r1+128]
    vptestmd     k3, m0, m0            ; n[32..47] != 0
    vmovdqu32    m0, [r1+192]
    vptestmd     k4, m0, m0            ; n[48..63] != 0
    kunpckwd     k1, k2, k1            ; bits 0..31
    kunpckwd     k3, k4, k3            ; bits 32..63 (in the low half)
    kunpckdq     k1, k3, k1            ; full 64-bit flat nonzero mask
    vpmovm2b     m0, k1                ; byte f = n[f] ? -1 : 0
    vmovdqu8     m1, [r2]              ; scan table
    vpermb       m0, m1, m0            ; byte s = nonzero(scan[s])
    vpmovb2m     k1, m0                ; scan-order mask
    vmovdqu8     m2, [trellis_iota_b]
    vpcompressb  m2{k1}{z}, m2         ; packed candidate positions
    movu         [r0], m2
    kmovq        r3, k1
    popcnt       rax, r3
    RET
%endif ; HAVE_MPEG2 && !HIGH_BIT_DEPTH

%macro DEQUANT_DC 2
cglobal dequant_4x4dc, 0,3,6
    DEQUANT_START 6, 6

.lshift:
%if cpuflag(avx2)
    vpbroadcastdct m3, [r1]
%else
    movd    xm3, [r1]
    SPLAT%1  m3, xm3
%endif
    movd    xm2, t0d
    pslld    m3, xm2
%assign %%x 0
%rep SIZEOF_PIXEL*32/mmsize
    %2       m0, m3, [r0+%%x]
    mova     [r0+%%x], m0
%assign %%x %%x+mmsize
%endrep
    RET

.rshift32:
    neg      t0d
%if cpuflag(avx2)
    vpbroadcastdct m2, [r1]
%else
    movd     xm2, [r1]
%endif
    mova      m5, [p%1_1]
    movd     xm3, t0d
    pslld     m4, m5, xm3
    psrld     m4, 1
%if HIGH_BIT_DEPTH
%if notcpuflag(avx2)
    pshufd    m2, m2, 0
%endif
%assign %%x 0
%rep SIZEOF_PIXEL*32/mmsize
    pmadcswd  m0, m2, [r0+%%x], m4
    psrad     m0, xm3
    mova      [r0+%%x], m0
%assign %%x %%x+mmsize
%endrep

%else ; !HIGH_BIT_DEPTH
%if notcpuflag(avx2)
    PSHUFLW   m2, m2, 0
%endif
    punpcklwd m2, m4
%assign %%x 0
%rep SIZEOF_PIXEL*32/mmsize
    mova      m0, [r0+%%x]
    punpckhwd m1, m0, m5
    punpcklwd m0, m5
    pmaddwd   m0, m2
    pmaddwd   m1, m2
    psrad     m0, xm3
    psrad     m1, xm3
    packssdw  m0, m1
    mova      [r0+%%x], m0
%assign %%x %%x+mmsize
%endrep
%endif ; !HIGH_BIT_DEPTH
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM sse2
DEQUANT_DC d, pmaddwd
INIT_XMM xop
DEQUANT_DC d, pmaddwd
INIT_YMM avx2
DEQUANT_DC d, pmaddwd
%else
%if ARCH_X86_64 == 0
INIT_MMX mmx2
DEQUANT_DC w, pmullw
%endif
INIT_XMM sse2
DEQUANT_DC w, pmullw
INIT_XMM avx
DEQUANT_DC w, pmullw
INIT_YMM avx2
DEQUANT_DC w, pmullw
%endif

%macro PEXTRW 4
    %if cpuflag(sse4)
        pextrw %1, %2, %3
    %else
        ; pextrw with a memory destination requires SSE4.1, go through a GPR as a fallback
        %if %3
            pextrw %4d, %2, %3
        %else
            movd %4d, %2
        %endif
        mov %1, %4w
    %endif
%endmacro

;-----------------------------------------------------------------------------
; void idct_dequant_2x4_dc( dctcoef dct[8], dctcoef dct4x4[8][16], int dequant_mf[6][16], int i_qp )
; void idct_dequant_2x4_dconly( dctcoef dct[8], int dequant_mf[6][16], int i_qp )
;-----------------------------------------------------------------------------

%macro DEQUANT_2x4_DC 1
%ifidn %1, dconly
    DECLARE_REG_TMP 6,3,2
    %define %%args dct, dmf, qp
%else
    DECLARE_REG_TMP 6,4,3
    %define %%args dct, dct4x4, dmf, qp
%endif

%if ARCH_X86_64 == 0
    DECLARE_REG_TMP 2,0,1
%endif

cglobal idct_dequant_2x4_%1, 0,3,5, %%args
    movifnidn  t2d, qpm
    imul       t0d, t2d, 0x2b
    shr        t0d, 8         ; qp / 6
    lea        t1d, [t0*5]
    sub        t2d, t0d
    sub        t2d, t1d       ; qp % 6
    shl        t2d, 6         ; 16 * sizeof(int)
%if ARCH_X86_64
    imul       t2d, [dmfq+t2], -0xffff ; (-dmf) << 16 | dmf
%else
    mov       dctq, dctmp
    add         t2, dmfmp
    imul       t2d, [t2], -0xffff
%endif
%if HIGH_BIT_DEPTH
    mova        m0, [dctq]
    mova        m1, [dctq+16]
    SUMSUB_BA    d, 1, 0, 2   ; 16-bit intermediate precision is enough for the first two sumsub steps,
    packssdw    m1, m0        ; and by packing to words we can use pmaddwd instead of pmulld later.
%else
    movq        m0, [dctq]
    movq        m1, [dctq+8]
    SUMSUB_BA    w, 1, 0, 2
    punpcklqdq  m1, m0        ; a0 a1 a2 a3 a4 a5 a6 a7
%endif
    pshufd      m0, m1, q2301 ; a2 a3 a0 a1 a6 a7 a4 a5
    movd        m3, t2d
    pshuflw     m3, m3, q1000 ; +  +  +  -
    SUMSUB_BA    w, 0, 1, 2
    punpcklqdq  m3, m3        ; +  +  +  -  +  +  +  -
    pshufd      m1, m1, q0022
    sub        t0d, 6
    jl .rshift
    movd        m2, t0d
    psllw       m3, m2
    pmaddwd     m0, m3
    pmaddwd     m1, m3
    jmp .end
.rshift:
    neg        t0d
    movd        m2, t0d
    pcmpeqd     m4, m4
    pmaddwd     m0, m3
    pmaddwd     m1, m3
    pslld       m4, m2
    psrad       m4, 1
    psubd       m0, m4 ; + 1 << (qp/6-1)
    psubd       m1, m4
    psrad       m0, m2
    psrad       m1, m2
.end:
%ifidn %1, dconly
%if HIGH_BIT_DEPTH
    mova    [dctq], m0
    mova [dctq+16], m1
%else
    packssdw    m0, m1
    mova    [dctq], m0
%endif
%else
    movifnidn dct4x4q, dct4x4mp
%if HIGH_BIT_DEPTH
    movd   [dct4x4q+0*64], m0
%if cpuflag(sse4)
    pextrd [dct4x4q+1*64], m0, 1
    add    dct4x4q, 4*64
    pextrd [dct4x4q-2*64], m0, 2
    pextrd [dct4x4q-1*64], m0, 3
    movd   [dct4x4q+0*64], m1
    pextrd [dct4x4q+1*64], m1, 1
    pextrd [dct4x4q+2*64], m1, 2
    pextrd [dct4x4q+3*64], m1, 3
%else
    MOVHL       m2, m0
    psrlq       m0, 32
    movd   [dct4x4q+1*64], m0
    add    dct4x4q, 4*64
    movd   [dct4x4q-2*64], m2
    psrlq       m2, 32
    movd   [dct4x4q-1*64], m2
    movd   [dct4x4q+0*64], m1
    MOVHL       m2, m1
    psrlq       m1, 32
    movd   [dct4x4q+1*64], m1
    movd   [dct4x4q+2*64], m2
    psrlq       m2, 32
    movd   [dct4x4q+3*64], m2
%endif
%else
    PEXTRW [dct4x4q+0*32], m0, 0, eax
    PEXTRW [dct4x4q+1*32], m0, 2, eax
    PEXTRW [dct4x4q+2*32], m0, 4, eax
    PEXTRW [dct4x4q+3*32], m0, 6, eax
    add    dct4x4q, 4*32
    PEXTRW [dct4x4q+0*32], m1, 0, eax
    PEXTRW [dct4x4q+1*32], m1, 2, eax
    PEXTRW [dct4x4q+2*32], m1, 4, eax
    PEXTRW [dct4x4q+3*32], m1, 6, eax
%endif
%endif
    RET
%endmacro

; sse4 reduces code size compared to sse2 but isn't any faster, so just go with sse2+avx
INIT_XMM sse2
DEQUANT_2x4_DC dc
DEQUANT_2x4_DC dconly
INIT_XMM avx
DEQUANT_2x4_DC dc
DEQUANT_2x4_DC dconly

; t4 is eax for return value.
%if ARCH_X86_64
    DECLARE_REG_TMP 0,1,2,3,6,4  ; Identical for both Windows and *NIX
%else
    DECLARE_REG_TMP 4,1,2,3,0,5
%endif

;-----------------------------------------------------------------------------
; x264_optimize_chroma_2x2_dc( dctcoef dct[4], int dequant_mf )
;-----------------------------------------------------------------------------

%macro OPTIMIZE_CHROMA_2x2_DC 0
cglobal optimize_chroma_2x2_dc, 0,6-cpuflag(sse4),7
    movifnidn t0, r0mp
    movd      m2, r1m
    movq      m1, [t0]
%if cpuflag(sse4)
    pcmpeqb   m4, m4
    pslld     m4, 11
%else
    pxor      m4, m4
%endif
%if cpuflag(ssse3)
    mova      m3, [chroma_dc_dct_mask]
    mova      m5, [chroma_dc_dmf_mask]
%else
    mova      m3, [chroma_dc_dct_mask_mmx]
    mova      m5, [chroma_dc_dmf_mask_mmx]
%endif
    pshuflw   m2, m2, 0
    pshufd    m0, m1, q0101      ;  1  0  3  2  1  0  3  2
    punpcklqdq m2, m2
    punpcklqdq m1, m1            ;  3  2  1  0  3  2  1  0
    mova      m6, [pd_1024]      ; 32<<5, elements are shifted 5 bits to the left
    PSIGNW    m0, m3             ; -1 -0  3  2 -1 -0  3  2
    PSIGNW    m2, m5             ;  +  -  -  +  -  -  +  +
    paddw     m0, m1             ; -1+3 -0+2  1+3  0+2 -1+3 -0+2  1+3  0+2
    pmaddwd   m0, m2             ;  0-1-2+3  0-1+2-3  0+1-2-3  0+1+2+3  * dmf
    punpcklwd m1, m1
    psrad     m2, 16             ;  +  -  -  +
    mov      t1d, 3
    paddd     m0, m6
    xor      t4d, t4d
%if notcpuflag(ssse3)
    psrad     m1, 31             ; has to be 0 or -1 in order for PSIGND_MMX to work correctly
%endif
%if cpuflag(sse4)
    ptest     m0, m4
%else
    mova      m6, m0
    SWAP       0, 6
    psrad     m6, 11
    pcmpeqd   m6, m4
    pmovmskb t5d, m6
    cmp      t5d, 0xffff
%endif
    jz .ret                      ; if the DC coefficients already round to zero, terminate early
    mova      m3, m0
.outer_loop:
    movsx    t3d, word [t0+2*t1] ; dct[coeff]
    pshufd    m6, m1, q3333
    pshufd    m1, m1, q2100      ; move the next element to high dword
    PSIGND    m5, m2, m6
    test     t3d, t3d
    jz .loop_end
.outer_loop_0:
    mov      t2d, t3d
    sar      t3d, 31
    or       t3d, 1
.inner_loop:
    psubd     m3, m5             ; coeff -= sign
    pxor      m6, m0, m3
%if cpuflag(sse4)
    ptest     m6, m4
%else
    psrad     m6, 11
    pcmpeqd   m6, m4
    pmovmskb t5d, m6
    cmp      t5d, 0xffff
%endif
    jz .round_coeff
    paddd     m3, m5             ; coeff += sign
    mov      t4d, 1
.loop_end:
    dec      t1d
    jz .last_coeff
    pshufd    m2, m2, q1320      ;  -  +  -  +  /  -  -  +  +
    jg .outer_loop
.ret:
    REP_RET
.round_coeff:
    sub      t2d, t3d
    mov [t0+2*t1], t2w
    jnz .inner_loop
    jmp .loop_end
.last_coeff:
    movsx    t3d, word [t0]
    punpcklqdq m2, m2            ;  +  +  +  +
    PSIGND    m5, m2, m1
    test     t3d, t3d
    jnz .outer_loop_0
    RET
%endmacro

%if HIGH_BIT_DEPTH == 0
INIT_XMM sse2
OPTIMIZE_CHROMA_2x2_DC
INIT_XMM ssse3
OPTIMIZE_CHROMA_2x2_DC
INIT_XMM sse4
OPTIMIZE_CHROMA_2x2_DC
INIT_XMM avx
OPTIMIZE_CHROMA_2x2_DC
%endif ; !HIGH_BIT_DEPTH

%if HIGH_BIT_DEPTH
;-----------------------------------------------------------------------------
; void denoise_dct( int32_t *dct, uint32_t *sum, uint32_t *offset, int size )
;-----------------------------------------------------------------------------
%macro DENOISE_DCT 0
cglobal denoise_dct, 4,4,6
    pxor      m5, m5
    movsxdifnidn r3, r3d
.loop:
    mova      m2, [r0+r3*4-2*mmsize]
    mova      m3, [r0+r3*4-1*mmsize]
    ABSD      m0, m2
    ABSD      m1, m3
    paddd     m4, m0, [r1+r3*4-2*mmsize]
    psubd     m0, [r2+r3*4-2*mmsize]
    mova      [r1+r3*4-2*mmsize], m4
    paddd     m4, m1, [r1+r3*4-1*mmsize]
    psubd     m1, [r2+r3*4-1*mmsize]
    mova      [r1+r3*4-1*mmsize], m4
    pcmpgtd   m4, m0, m5
    pand      m0, m4
    pcmpgtd   m4, m1, m5
    pand      m1, m4
    PSIGND    m0, m2
    PSIGND    m1, m3
    mova      [r0+r3*4-2*mmsize], m0
    mova      [r0+r3*4-1*mmsize], m1
    sub      r3d, mmsize/2
    jg .loop
    RET
%endmacro

%if ARCH_X86_64 == 0
INIT_MMX mmx
DENOISE_DCT
%endif
INIT_XMM sse2
DENOISE_DCT
INIT_XMM ssse3
DENOISE_DCT
INIT_XMM avx
DENOISE_DCT
INIT_YMM avx2
DENOISE_DCT

%else ; !HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; void denoise_dct( int16_t *dct, uint32_t *sum, uint16_t *offset, int size )
;-----------------------------------------------------------------------------
%macro DENOISE_DCT 0
cglobal denoise_dct, 4,4,7
    pxor      m6, m6
    movsxdifnidn r3, r3d
.loop:
    mova      m2, [r0+r3*2-2*mmsize]
    mova      m3, [r0+r3*2-1*mmsize]
    ABSW      m0, m2, sign
    ABSW      m1, m3, sign
    psubusw   m4, m0, [r2+r3*2-2*mmsize]
    psubusw   m5, m1, [r2+r3*2-1*mmsize]
    PSIGNW    m4, m2
    PSIGNW    m5, m3
    mova      [r0+r3*2-2*mmsize], m4
    mova      [r0+r3*2-1*mmsize], m5
    punpcklwd m2, m0, m6
    punpcklwd m3, m1, m6
    punpckhwd m0, m6
    punpckhwd m1, m6
    paddd     m2, [r1+r3*4-4*mmsize]
    paddd     m0, [r1+r3*4-3*mmsize]
    paddd     m3, [r1+r3*4-2*mmsize]
    paddd     m1, [r1+r3*4-1*mmsize]
    mova      [r1+r3*4-4*mmsize], m2
    mova      [r1+r3*4-3*mmsize], m0
    mova      [r1+r3*4-2*mmsize], m3
    mova      [r1+r3*4-1*mmsize], m1
    sub       r3, mmsize
    jg .loop
    RET
%endmacro

%if ARCH_X86_64 == 0
INIT_MMX mmx
DENOISE_DCT
%endif
INIT_XMM sse2
DENOISE_DCT
INIT_XMM ssse3
DENOISE_DCT
INIT_XMM avx
DENOISE_DCT

INIT_YMM avx2
cglobal denoise_dct, 4,4,4
    pxor      m3, m3
    movsxdifnidn r3, r3d
.loop:
    mova      m1, [r0+r3*2-mmsize]
    pabsw     m0, m1
    psubusw   m2, m0, [r2+r3*2-mmsize]
    vpermq    m0, m0, q3120
    psignw    m2, m1
    mova [r0+r3*2-mmsize], m2
    punpcklwd m1, m0, m3
    punpckhwd m0, m3
    paddd     m1, [r1+r3*4-2*mmsize]
    paddd     m0, [r1+r3*4-1*mmsize]
    mova      [r1+r3*4-2*mmsize], m1
    mova      [r1+r3*4-1*mmsize], m0
    sub       r3, mmsize/2
    jg .loop
    RET

%endif ; !HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; int decimate_score( dctcoef *dct )
;-----------------------------------------------------------------------------

%macro DECIMATE_MASK 4
%if HIGH_BIT_DEPTH
    mova      m0, [%3+0*16]
    packssdw  m0, [%3+1*16]
    mova      m1, [%3+2*16]
    packssdw  m1, [%3+3*16]
    ABSW2     m0, m1, m0, m1, m3, m4
%else
    ABSW      m0, [%3+ 0], m3
    ABSW      m1, [%3+16], m4
%endif
    packsswb  m0, m1
    pxor      m2, m2
    pcmpeqb   m2, m0
    pcmpgtb   m0, %4
    pmovmskb  %1, m2
    pmovmskb  %2, m0
%endmacro

%macro DECIMATE_MASK16_AVX512 0
    mova      m0, [r0]
%if HIGH_BIT_DEPTH
    vptestmd  k0, m0, m0
    pabsd     m0, m0
    vpcmpud   k1, m0, [pd_1] {1to16}, 6
%else
    vptestmw  k0, m0, m0
    pabsw     m0, m0
    vpcmpuw   k1, m0, [pw_1], 6
%endif
%endmacro

%macro SHRX 2
%if cpuflag(bmi2)
    shrx %1, %1, %2
%else
    shr  %1, %2b ; %2 has to be rcx/ecx
%endif
%endmacro

%macro BLSR 2
%if cpuflag(bmi1)
    blsr   %1, %2
%else
    lea    %1, [%2-1]
    and    %1, %2
%endif
%endmacro

cextern_common decimate_table4
cextern_common decimate_table8

%macro DECIMATE4x4 1

cglobal decimate_score%1, 1,3
%if cpuflag(avx512)
    DECIMATE_MASK16_AVX512
    xor   eax, eax
    kmovw edx, k0
%if %1 == 15
    shr   edx, 1
%else
    test  edx, edx
%endif
    jz .ret
    ktestw k1, k1
    jnz .ret9
%else
    DECIMATE_MASK edx, eax, r0, [pb_1]
    xor   edx, 0xffff
    jz .ret
    test  eax, eax
    jnz .ret9
%if %1 == 15
    shr   edx, 1
%endif
%endif
%if ARCH_X86_64
    lea    r4, [decimate_mask_table4]
    %define mask_table r4
%else
    %define mask_table decimate_mask_table4
%endif
    movzx ecx, dl
    movzx eax, byte [mask_table + rcx]
%if ARCH_X86_64
    xor   edx, ecx
    jz .ret
%if cpuflag(lzcnt)
    lzcnt ecx, ecx
    lea    r5, [decimate_table4-32]
    add    r5, rcx
%else
    bsr   ecx, ecx
    lea    r5, [decimate_table4-1]
    sub    r5, rcx
%endif
    %define table r5
%else
    cmp   edx, ecx
    jz .ret
    bsr   ecx, ecx
    shr   edx, 1
    SHRX  edx, ecx
    %define table decimate_table4
%endif
    tzcnt ecx, edx
    shr   edx, 1
    SHRX  edx, ecx
    add    al, byte [table + rcx]
    add    al, byte [mask_table + rdx]
.ret:
    REP_RET
.ret9:
    mov   eax, 9
    RET
%endmacro

%macro DECIMATE_MASK64_AVX2 2 ; nz_low, nz_high
    mova      m0, [r0+0*32]
    packsswb  m0, [r0+1*32]
    mova      m1, [r0+2*32]
    packsswb  m1, [r0+3*32]
    mova      m4, [pb_1]
    pabsb     m2, m0
    pabsb     m3, m1
    por       m2, m3 ; the > 1 checks don't care about order, so
    ptest     m4, m2 ; we can save latency by doing them here
    jnc .ret9
    vpermq    m0, m0, q3120
    vpermq    m1, m1, q3120
    pxor      m4, m4
    pcmpeqb   m0, m4
    pcmpeqb   m1, m4
    pmovmskb  %1, m0
    pmovmskb  %2, m1
%endmacro

%macro DECIMATE_MASK64_AVX512 0
    mova            m0, [r0]
%if HIGH_BIT_DEPTH
    packssdw        m0, [r0+1*64]
    mova            m1, [r0+2*64]
    packssdw        m1, [r0+3*64]
    packsswb        m0, m1
    vbroadcasti32x4 m1, [pb_1]
    pabsb           m2, m0
    vpcmpub         k0, m2, m1, 6
    ktestq          k0, k0
    jnz .ret9
    mova            m1, [decimate_shuf_avx512]
    vpermd          m0, m1, m0
    vptestmb        k1, m0, m0
%else
    mova            m1, [r0+64]
    vbroadcasti32x4 m3, [pb_1]
    packsswb        m2, m0, m1
    pabsb           m2, m2
    vpcmpub         k0, m2, m3, 6
    ktestq          k0, k0
    jnz .ret9
    vptestmw        k1, m0, m0
    vptestmw        k2, m1, m1
%endif
%endmacro

%macro DECIMATE8x8 0
%if ARCH_X86_64
cglobal decimate_score64, 1,5
%if mmsize == 64
    DECIMATE_MASK64_AVX512
    xor     eax, eax
%if HIGH_BIT_DEPTH
    kmovq    r1, k1
    test     r1, r1
    jz .ret
%else
    kortestd k1, k2
    jz .ret
    kunpckdq k1, k2, k1
    kmovq    r1, k1
%endif
%elif mmsize == 32
    DECIMATE_MASK64_AVX2 r1d, eax
    not    r1
    shl   rax, 32
    xor    r1, rax
    jz .ret
%else
    mova   m5, [pb_1]
    DECIMATE_MASK r1d, eax, r0+SIZEOF_DCTCOEF* 0, m5
    test  eax, eax
    jnz .ret9
    DECIMATE_MASK r2d, eax, r0+SIZEOF_DCTCOEF*16, m5
    shl   r2d, 16
    or    r1d, r2d
    DECIMATE_MASK r2d, r3d, r0+SIZEOF_DCTCOEF*32, m5
    shl    r2, 32
    or    eax, r3d
    or     r1, r2
    DECIMATE_MASK r2d, r3d, r0+SIZEOF_DCTCOEF*48, m5
    not    r1
    shl    r2, 48
    xor    r1, r2
    jz .ret
    add   eax, r3d
    jnz .ret9
%endif
    lea    r4, [decimate_table8]
    mov    al, -6
.loop:
    tzcnt rcx, r1
    add    al, byte [r4 + rcx]
    jge .ret9
    shr    r1, 1
    SHRX   r1, rcx
%if cpuflag(bmi2)
    test   r1, r1
%endif
    jnz .loop
    add    al, 6
.ret:
    REP_RET
.ret9:
    mov   eax, 9
    RET

%else ; ARCH
cglobal decimate_score64, 1,4
%if mmsize == 64
    DECIMATE_MASK64_AVX512
    xor     eax, eax
%if HIGH_BIT_DEPTH
    kshiftrq k2, k1, 32
%endif
    kmovd    r2, k1
    kmovd    r3, k2
    test     r2, r2
    jz .tryret
%elif mmsize == 32
    DECIMATE_MASK64_AVX2 r2, r3
    xor   eax, eax
    not    r3
    xor    r2, -1
    jz .tryret
%else
    mova   m5, [pb_1]
    DECIMATE_MASK r2, r1, r0+SIZEOF_DCTCOEF* 0, m5
    test   r1, r1
    jnz .ret9
    DECIMATE_MASK r3, r1, r0+SIZEOF_DCTCOEF*16, m5
    not    r2
    shl    r3, 16
    xor    r2, r3
    mov   r0m, r2
    DECIMATE_MASK r3, r2, r0+SIZEOF_DCTCOEF*32, m5
    or     r2, r1
    DECIMATE_MASK r1, r0, r0+SIZEOF_DCTCOEF*48, m5
    add    r0, r2
    jnz .ret9
    mov    r2, r0m
    not    r3
    shl    r1, 16
    xor    r3, r1
    test   r2, r2
    jz .tryret
%endif
    mov    al, -6
.loop:
    tzcnt ecx, r2
    add    al, byte [decimate_table8 + ecx]
    jge .ret9
    sub   ecx, 31 ; increase the shift count by one to shift away the lowest set bit as well
    jz .run31     ; only bits 0-4 are used so we have to explicitly handle the case of 1<<31
    shrd   r2, r3, cl
    SHRX   r3, ecx
%if notcpuflag(bmi2)
    test   r2, r2
%endif
    jnz .loop
    BLSR   r2, r3
    jz .end
.largerun:
    tzcnt ecx, r3
    shr    r3, 1
    SHRX   r3, ecx
.loop2:
    tzcnt ecx, r3
    add    al, byte [decimate_table8 + ecx]
    jge .ret9
    shr    r3, 1
    SHRX   r3, ecx
.run31:
    test   r3, r3
    jnz .loop2
.end:
    add    al, 6
    RET
.tryret:
    BLSR   r2, r3
    jz .ret
    mov    al, -6
    jmp .largerun
.ret9:
    mov   eax, 9
.ret:
    REP_RET
%endif ; ARCH
%endmacro

INIT_XMM sse2
DECIMATE4x4 15
DECIMATE4x4 16
DECIMATE8x8
INIT_XMM ssse3
DECIMATE4x4 15
DECIMATE4x4 16
DECIMATE8x8
%if HIGH_BIT_DEPTH
INIT_ZMM avx512
%else
INIT_YMM avx2
DECIMATE8x8
INIT_YMM avx512
%endif
DECIMATE4x4 15
DECIMATE4x4 16
INIT_ZMM avx512
DECIMATE8x8

;-----------------------------------------------------------------------------
; int coeff_last( dctcoef *dct )
;-----------------------------------------------------------------------------

%macro BSR 3
%if cpuflag(lzcnt)
    lzcnt %1, %2
    xor %1, %3
%else
    bsr %1, %2
%endif
%endmacro

%macro LZCOUNT 3
%if cpuflag(lzcnt)
    lzcnt %1, %2
%else
    bsr %1, %2
    xor %1, %3
%endif
%endmacro

%if HIGH_BIT_DEPTH
%macro LAST_MASK 3-4
%if %1 == 4
    movq     mm0, [%3]
    packssdw mm0, [%3+8]
    packsswb mm0, mm0
    pcmpeqb  mm0, mm2
    pmovmskb  %2, mm0
%elif mmsize == 16
    movdqa   xmm0, [%3+ 0]
%if %1 == 8
    packssdw xmm0, [%3+16]
    packsswb xmm0, xmm0
%else
    movdqa   xmm1, [%3+32]
    packssdw xmm0, [%3+16]
    packssdw xmm1, [%3+48]
    packsswb xmm0, xmm1
%endif
    pcmpeqb  xmm0, xmm2
    pmovmskb   %2, xmm0
%elif %1 == 8
    movq     mm0, [%3+ 0]
    movq     mm1, [%3+16]
    packssdw mm0, [%3+ 8]
    packssdw mm1, [%3+24]
    packsswb mm0, mm1
    pcmpeqb  mm0, mm2
    pmovmskb  %2, mm0
%else
    movq     mm0, [%3+ 0]
    movq     mm1, [%3+16]
    packssdw mm0, [%3+ 8]
    packssdw mm1, [%3+24]
    movq     mm3, [%3+32]
    movq     mm4, [%3+48]
    packssdw mm3, [%3+40]
    packssdw mm4, [%3+56]
    packsswb mm0, mm1
    packsswb mm3, mm4
    pcmpeqb  mm0, mm2
    pcmpeqb  mm3, mm2
    pmovmskb  %2, mm0
    pmovmskb  %4, mm3
    shl       %4, 8
    or        %2, %4
%endif
%endmacro

%macro COEFF_LAST4 0
cglobal coeff_last4, 1,3
    pxor mm2, mm2
    LAST_MASK 4, r1d, r0
    xor  r1d, 0xff
    shr  r1d, 4
    BSR  eax, r1d, 0x1f
    RET
%endmacro

INIT_MMX mmx2
COEFF_LAST4
INIT_MMX lzcnt
COEFF_LAST4

%macro COEFF_LAST8 0
cglobal coeff_last8, 1,3
    pxor m2, m2
    LAST_MASK 8, r1d, r0
%if mmsize == 16
    xor r1d, 0xffff
    shr r1d, 8
%else
    xor r1d, 0xff
%endif
    BSR eax, r1d, 0x1f
    RET
%endmacro

%if ARCH_X86_64 == 0
INIT_MMX mmx2
COEFF_LAST8
%endif
INIT_XMM sse2
COEFF_LAST8
INIT_XMM lzcnt
COEFF_LAST8

%else ; !HIGH_BIT_DEPTH
%macro LAST_MASK 3-4
%if %1 <= 8
    movq     mm0, [%3+ 0]
%if %1 == 4
    packsswb mm0, mm0
%else
    packsswb mm0, [%3+ 8]
%endif
    pcmpeqb  mm0, mm2
    pmovmskb  %2, mm0
%elif mmsize == 16
    movdqa   xmm0, [%3+ 0]
    packsswb xmm0, [%3+16]
    pcmpeqb  xmm0, xmm2
    pmovmskb   %2, xmm0
%else
    movq     mm0, [%3+ 0]
    movq     mm1, [%3+16]
    packsswb mm0, [%3+ 8]
    packsswb mm1, [%3+24]
    pcmpeqb  mm0, mm2
    pcmpeqb  mm1, mm2
    pmovmskb  %2, mm0
    pmovmskb  %4, mm1
    shl       %4, 8
    or        %2, %4
%endif
%endmacro

%macro COEFF_LAST48 0
%if ARCH_X86_64
cglobal coeff_last4, 1,1
    BSR  rax, [r0], 0x3f
    shr  eax, 4
    RET
%else
cglobal coeff_last4, 0,3
    mov   edx, r0mp
    mov   eax, [edx+4]
    xor   ecx, ecx
    test  eax, eax
    cmovz eax, [edx]
    setnz cl
    BSR   eax, eax, 0x1f
    shr   eax, 4
    lea   eax, [eax+ecx*2]
    RET
%endif

cglobal coeff_last8, 1,3
    pxor m2, m2
    LAST_MASK 8, r1d, r0, r2d
    xor r1d, 0xff
    BSR eax, r1d, 0x1f
    RET
%endmacro

INIT_MMX mmx2
COEFF_LAST48
INIT_MMX lzcnt
COEFF_LAST48
%endif ; HIGH_BIT_DEPTH

%macro COEFF_LAST 0
cglobal coeff_last15, 1,3
    pxor m2, m2
    LAST_MASK 15, r1d, r0-SIZEOF_DCTCOEF, r2d
    xor r1d, 0xffff
    BSR eax, r1d, 0x1f
    dec eax
    RET

cglobal coeff_last16, 1,3
    pxor m2, m2
    LAST_MASK 16, r1d, r0, r2d
    xor r1d, 0xffff
    BSR eax, r1d, 0x1f
    RET

%if ARCH_X86_64 == 0
cglobal coeff_last64, 1, 4-mmsize/16
    pxor m2, m2
    LAST_MASK 16, r1d, r0+SIZEOF_DCTCOEF* 32, r3d
    LAST_MASK 16, r2d, r0+SIZEOF_DCTCOEF* 48, r3d
    shl r2d, 16
    or  r1d, r2d
    xor r1d, -1
    jne .secondhalf
    LAST_MASK 16, r1d, r0+SIZEOF_DCTCOEF* 0, r3d
    LAST_MASK 16, r2d, r0+SIZEOF_DCTCOEF*16, r3d
    shl r2d, 16
    or  r1d, r2d
    not r1d
    BSR eax, r1d, 0x1f
    RET
.secondhalf:
    BSR eax, r1d, 0x1f
    add eax, 32
    RET
%else
cglobal coeff_last64, 1,3
    pxor m2, m2
    LAST_MASK 16, r1d, r0+SIZEOF_DCTCOEF* 0
    LAST_MASK 16, r2d, r0+SIZEOF_DCTCOEF*16
    shl r2d, 16
    or  r1d, r2d
    LAST_MASK 16, r2d, r0+SIZEOF_DCTCOEF*32
    LAST_MASK 16, r0d, r0+SIZEOF_DCTCOEF*48
    shl r0d, 16
    or  r2d, r0d
    shl  r2, 32
    or   r1, r2
    not  r1
    BSR rax, r1, 0x3f
    RET
%endif
%endmacro

%if ARCH_X86_64 == 0
INIT_MMX mmx2
COEFF_LAST
%endif
INIT_XMM sse2
COEFF_LAST
INIT_XMM lzcnt
COEFF_LAST

%macro LAST_MASK_AVX2 2
%if HIGH_BIT_DEPTH
    mova     m0, [%2+ 0]
    packssdw m0, [%2+32]
    mova     m1, [%2+64]
    packssdw m1, [%2+96]
    packsswb m0, m1
    mova     m1, [deinterleave_shufd]
    vpermd   m0, m1, m0
%else
    mova     m0, [%2+ 0]
    packsswb m0, [%2+32]
    vpermq   m0, m0, q3120
%endif
    pcmpeqb  m0, m2
    pmovmskb %1, m0
%endmacro

%if ARCH_X86_64 == 0
INIT_YMM avx2
cglobal coeff_last64, 1,2
    pxor m2, m2
    LAST_MASK_AVX2 r1d, r0+SIZEOF_DCTCOEF*32
    xor r1d, -1
    jne .secondhalf
    LAST_MASK_AVX2 r1d, r0+SIZEOF_DCTCOEF* 0
    not r1d
    BSR eax, r1d, 0x1f
    RET
.secondhalf:
    BSR eax, r1d, 0x1f
    add eax, 32
    RET
%else
INIT_YMM avx2
cglobal coeff_last64, 1,3
    pxor m2, m2
    LAST_MASK_AVX2 r1d, r0+SIZEOF_DCTCOEF* 0
    LAST_MASK_AVX2 r2d, r0+SIZEOF_DCTCOEF*32
    shl  r2, 32
    or   r1, r2
    not  r1
    BSR rax, r1, 0x3f
    RET
%endif

%macro COEFF_LAST_AVX512 2 ; num, w/d
cglobal coeff_last%1, 1,2
    mova         m0, [r0-(%1&1)*SIZEOF_DCTCOEF]
    vptestm%2    k0, m0, m0
%if %1 == 15
    mov         eax, 30
    kmovw       r1d, k0
    lzcnt       r1d, r1d
    sub         eax, r1d
%else
    kmovw       eax, k0
    lzcnt       eax, eax
    xor         eax, 31
%endif
    RET
%endmacro

%macro COEFF_LAST64_AVX512 1 ; w/d
cglobal coeff_last64, 1,2
    pxor        xm0, xm0
    vpcmp%1      k0, m0, [r0+0*64], 4
    vpcmp%1      k1, m0, [r0+1*64], 4
%if HIGH_BIT_DEPTH
    vpcmp%1      k2, m0, [r0+2*64], 4
    vpcmp%1      k3, m0, [r0+3*64], 4
    kunpckwd     k0, k1, k0
    kunpckwd     k1, k3, k2
%endif
%if ARCH_X86_64
    kunpckdq     k0, k1, k0
    kmovq       rax, k0
    lzcnt       rax, rax
    xor         eax, 63
%else
    kmovd       r1d, k1
    kmovd       eax, k0
    lzcnt       r1d, r1d
    lzcnt       eax, eax
    xor         r1d, 32
    cmovnz      eax, r1d
    xor         eax, 31
%endif
    RET
%endmacro

%if HIGH_BIT_DEPTH
INIT_XMM avx512
COEFF_LAST_AVX512  4, d
INIT_YMM avx512
COEFF_LAST_AVX512  8, d
INIT_ZMM avx512
COEFF_LAST_AVX512 15, d
COEFF_LAST_AVX512 16, d
COEFF_LAST64_AVX512 d
%else ; !HIGH_BIT_DEPTH
INIT_XMM avx512
COEFF_LAST_AVX512  8, w
INIT_YMM avx512
COEFF_LAST_AVX512 15, w
COEFF_LAST_AVX512 16, w
INIT_ZMM avx512
COEFF_LAST64_AVX512 w
%endif ; !HIGH_BIT_DEPTH

;-----------------------------------------------------------------------------
; int coeff_level_run( dctcoef *dct, run_level_t *runlevel )
;-----------------------------------------------------------------------------

struc levelrun
    .last: resd 1
    .mask: resd 1
%if HAVE_MPEG2
    align 64, resb 1
    .level: resw 64
    .mask64: resq 1
%else
    align 16, resb 1
    .level: resw 16
%endif
endstruc

; t6 = eax for return, t3 = ecx for shift, t[01] = r[01] for x86_64 args
%if WIN64
    DECLARE_REG_TMP 3,1,2,0,4,5,6
%elif ARCH_X86_64
    DECLARE_REG_TMP 0,1,2,3,4,5,6
%else
    DECLARE_REG_TMP 6,3,2,1,4,5,0
%endif

%macro COEFF_LEVELRUN 1
cglobal coeff_level_run%1,0,7
    movifnidn t0, r0mp
    movifnidn t1, r1mp
    pxor    m2, m2
    xor    t3d, t3d
    LAST_MASK %1, t5d, t0-(%1&1)*SIZEOF_DCTCOEF, t4d
%if %1==15
    shr    t5d, 1
%elif %1==8
    and    t5d, 0xff
%elif %1==4
    and    t5d, 0xf
%endif
    xor    t5d, (1<<%1)-1
    mov [t1+levelrun.mask], t5d
    shl    t5d, 32-%1
    mov    t4d, %1-1
    LZCOUNT t3d, t5d, 0x1f
    xor    t6d, t6d
    add    t5d, t5d
    sub    t4d, t3d
    shl    t5d, t3b
    mov [t1+levelrun.last], t4d
.loop:
    LZCOUNT t3d, t5d, 0x1f
%if HIGH_BIT_DEPTH
    mov    t2d, [t0+t4*4]
%else
    mov    t2w, [t0+t4*2]
%endif
    inc    t3d
    shl    t5d, t3b
%if HIGH_BIT_DEPTH
    mov   [t1+t6*4+levelrun.level], t2d
%else
    mov   [t1+t6*2+levelrun.level], t2w
%endif
    inc    t6d
    sub    t4d, t3d
    jge .loop
    RET
%endmacro

INIT_MMX mmx2
%if ARCH_X86_64 == 0
COEFF_LEVELRUN 15
COEFF_LEVELRUN 16
%endif
COEFF_LEVELRUN 4
COEFF_LEVELRUN 8
INIT_XMM sse2
%if HIGH_BIT_DEPTH
COEFF_LEVELRUN 8
%endif
COEFF_LEVELRUN 15
COEFF_LEVELRUN 16
INIT_MMX lzcnt
COEFF_LEVELRUN 4
%if HIGH_BIT_DEPTH == 0
COEFF_LEVELRUN 8
%endif
INIT_XMM lzcnt
%if HIGH_BIT_DEPTH
COEFF_LEVELRUN 8
%endif
COEFF_LEVELRUN 15
COEFF_LEVELRUN 16

%if HAVE_MPEG2 && ARCH_X86_64 && HIGH_BIT_DEPTH == 0
; t5 = 64-bit nonzero mask, t0 = dct, t1 = runlevel
%macro LEVELRUN64_TAIL 0
    mov [t1+levelrun.mask64], t5
    xor    t6d, t6d
; An all-zero block has mask 0: last = -1, no coefficients. bsr/lzcnt of 0 are
; unreliable, so handle it explicitly and skip the loop so it never reads
; dct[-1]. Matches coeff_level_run64.
    mov    t4d, -1
    test    t5, t5
    jz .empty
    mov    t4d, 63
    LZCOUNT t3, t5, 0x3f
    sub    t4d, t3d
    mov [t1+levelrun.last], t4d
    add     t5, t5
    shl     t5, t3b
.loop:
    LZCOUNT t3, t5, 0x3f
    mov    t2w, [t0+t4*2]
    inc    t3d
    shl     t5, t3b
    mov   [t1+t6*2+levelrun.level], t2w
    inc    t6d
    sub    t4d, t3d
    jge .loop
    RET
.empty:
    mov [t1+levelrun.last], t4d
    RET
%endmacro

%macro COEFF_LEVELRUN64 0
cglobal coeff_level_run64,0,7
    movifnidn t0, r0mp
    movifnidn t1, r1mp
    pxor    m2, m2
    xor    t3d, t3d
    LAST_MASK 16, t5d, t0+SIZEOF_DCTCOEF* 0, t4d
    LAST_MASK 16, t4d, t0+SIZEOF_DCTCOEF*16, t6d
    shl    t4d, 16
    or     t5d, t4d
    LAST_MASK 16, t4d, t0+SIZEOF_DCTCOEF*32, t6d
    LAST_MASK 16, t6d, t0+SIZEOF_DCTCOEF*48, t2d
    shl    t6d, 16
    or     t4d, t6d
    shl     t4, 32
    or      t5, t4
    not     t5
    LEVELRUN64_TAIL
%endmacro

INIT_XMM sse2
COEFF_LEVELRUN64
INIT_XMM lzcnt
COEFF_LEVELRUN64

%macro COEFF_LEVELRUN64_AVX512 0
cglobal coeff_level_run64,0,7
    movifnidn t0, r0mp
    movifnidn t1, r1mp
    xor    t3d, t3d
    vpxord  m0, m0, m0
    vpcmpw  k0, m0, [t0+0*64], 4
    vpcmpw  k1, m0, [t0+1*64], 4
    kunpckdq k0, k1, k0
    kmovq   t5, k0
    LEVELRUN64_TAIL
%endmacro

INIT_ZMM avx512
COEFF_LEVELRUN64_AVX512

%macro COEFF_LEVELRUN64_AVX512ICL 0
cglobal coeff_level_run64, 2,4
    vpxord       m0, m0, m0
    mova         m4, [levelrun_reverse_avx512]
    vpermw       m1, m4, [r0+0*64]
    vpermw       m2, m4, [r0+1*64]
    vpcmpw       k0, m0, [r0+0*64], 4
    vpcmpw       k1, m0, [r0+1*64], 4
    vpcmpw       k2, m0, m2, 4
    vpcmpw       k3, m0, m1, 4
    kunpckdq     k0, k1, k0
    kmovq        r2, k0
    lzcnt        rax, r2
    xor          eax, 63
; all-zero block: lzcnt 0 = 64, 64^63 = 127; last must be -1 (matches
; coeff_level_run64). The empty vpcompressw stores below are harmless.
    mov          r3d, -1
    test         r2, r2
    cmovz        eax, r3d
    mov [r1+levelrun.last], eax
    mov [r1+levelrun.mask64], r2
; vpcompressw to a register is 2 uops; a memory destination is microcoded
; (~250 uops) on Zen4, so compress into a register and store separately.
    vpcompressw  m2{k2}{z}, m2
    mova [r1+levelrun.level], m2
    kmovd        r3d, k2
    popcnt       r3d, r3d
    vpcompressw  m1{k3}{z}, m1
    movu [r1+r3*2+levelrun.level], m1
    popcnt       rax, r2
    RET
%endmacro

INIT_ZMM avx512icl
COEFF_LEVELRUN64_AVX512ICL

; Gather one group of 8 coefficients using the pshufb LUT, like the run15/16
; LUT below. %1 = group index (0 = coeffs 0-7 .. 7 = coeffs 56-63), running
; word offset in r4, mask byte in r3b/r3d, scratch xmm m0/m1.
%macro LEVELRUN64_LUT_GROUP 1
    movzx     r3d, byte [r1+levelrun.mask64+%1]
    movh       m1, [dct_coef_shuffle+r3*8 GLOBAL]
    punpcklbw  m1, m1
    por        m1, m4
    mova       m0, [r0+16*%1]
    pshufb     m0, m1
    movu [r1+r4*2+levelrun.level], m0
    movzx     r3d, byte [popcnt_table+r3 GLOBAL]
    add       r4d, r3d
%endmacro

%macro COEFF_LEVELRUN64_LUT 0
cglobal coeff_level_run64, 2,5
    lea        r2, [$$]
    %define GLOBAL +r2-$$
    pxor      xm5, xm5
    mova       m0, [r0+ 0]
    packsswb   m0, [r0+16]
    mova       m1, [r0+32]
    packsswb   m1, [r0+48]
    pcmpeqb    m0, m5
    pcmpeqb    m1, m5
    pmovmskb  eax, m0
    pmovmskb  r3d, m1
    shl        r3, 16
    or        rax, r3
    mova       m0, [r0+64]
    packsswb   m0, [r0+80]
    mova       m1, [r0+96]
    packsswb   m1, [r0+112]
    pcmpeqb    m0, m5
    pcmpeqb    m1, m5
    pmovmskb  r3d, m0
    shl        r3, 32
    or        rax, r3
    pmovmskb  r3d, m1
    shl        r3, 48
    or        rax, r3
    not       rax
    mov [r1+levelrun.mask64], rax
    lzcnt      r2, rax
    xor        r2d, 63
; all-zero block: lzcnt 0 = 64, 64^63 = 127; last must be -1 (matches
; coeff_level_run64). The LUT groups below write nothing when the mask is 0.
    mov       r3d, -1
    test      rax, rax
    cmovz     r2d, r3d
    mov [r1+levelrun.last], r2d
    lea        r2, [$$]
    mova       m4, [pw_256 GLOBAL]
    xor       r4d, r4d
    %assign %%g 7
    %rep 8
        LEVELRUN64_LUT_GROUP %%g
        %assign %%g %%g-1
    %endrep
; The overlapping unaligned stores above can spill past level[63] into the
; mask64 field, so write it again here.
    mov [r1+levelrun.mask64], rax
    mov       eax, r4d
    RET
%endmacro

INIT_XMM ssse3
COEFF_LEVELRUN64_LUT

; AVX2 variant: gather 16 coefficients per group, modeled on the run15/16 avx2
; LUT below. %1 = group index (0 = coeffs 0-15 .. 3 = coeffs 48-63). r5 = mask64,
; r7 = $$ base, r4 = running word offset, scratches r2/r3, xmm m0/m2.
%macro LEVELRUN64_LUT_GROUP_AVX2 1
    mov        r2, r5
    shr        r2, %1*16
    movzx     r3d, r2b  ; coeffs %1*16+0..7
    shr       r2d, 8
    movzx     r2d, r2b  ; coeffs %1*16+8..15
    movq     xm2, [dct_coef_shuffle+r3*8 GLOBAL]
    vinserti128 m2, m2, [dct_coef_shuffle+r2*8 GLOBAL], 1
    punpcklbw  m2, m2
    por        m2, m4
    pshufb     m0, [r0+32*%1], m2
    movzx     r2d, byte [popcnt_table+r2 GLOBAL]
    movzx     r3d, byte [popcnt_table+r3 GLOBAL]
    vextracti128 [r1+r4*2+levelrun.level], m0, 1
    add       r2d, r4d
    movu [r1+r2*2+levelrun.level], xm0
    lea       r4d, [r2+r3]
%endmacro

%macro COEFF_LEVELRUN64_LUT_AVX2 0
cglobal coeff_level_run64, 2,8
    lea        r7, [$$]
    %define GLOBAL +r7-$$
    pxor      xm5, xm5
    mova       m0, [r0+ 0]
    packsswb   m0, [r0+32]
    vpermq     m0, m0, q3120
    mova       m1, [r0+64]
    packsswb   m1, [r0+96]
    vpermq     m1, m1, q3120
    pcmpeqb    m0, m5
    pcmpeqb    m1, m5
    pmovmskb  eax, m0
    pmovmskb  r3d, m1
    shl        r3, 32
    or        rax, r3
    not       rax
    mov        r5, rax
    lzcnt      r3, rax
    xor        r3d, 63
; all-zero block: lzcnt 0 = 64, 64^63 = 127; last must be -1 (matches
; coeff_level_run64). The LUT groups below write nothing when the mask is 0.
    mov       eax, -1
    test      r5, r5
    cmovz     r3d, eax
    mov [r1+levelrun.last], r3d
    vpbroadcastw m4, [pw_256 GLOBAL]
    xor       r4d, r4d
    %assign %%g 3
    %rep 4
        LEVELRUN64_LUT_GROUP_AVX2 %%g
        %assign %%g %%g-1
    %endrep
    mov [r1+levelrun.mask64], r5
    mov       eax, r4d
    RET
%endmacro

INIT_YMM avx2
COEFF_LEVELRUN64_LUT_AVX2
%endif

; Similar to the one above, but saves the DCT
; coefficients in m0/m1 so we don't have to load
; them later.
%macro LAST_MASK_LUT 3
    pxor     xm5, xm5
%if %1 <= 8
    mova      m0, [%3]
    packsswb  m2, m0, m0
%else
    mova     xm0, [%3+ 0]
    mova     xm1, [%3+16]
    packsswb xm2, xm0, xm1
%if mmsize==32
    vinserti128 m0, m0, xm1, 1
%endif
%endif
    pcmpeqb  xm2, xm5
    pmovmskb  %2, xm2
%endmacro

%macro COEFF_LEVELRUN_LUT 1
cglobal coeff_level_run%1,2,4+(%1/9)
%if ARCH_X86_64
    lea       r5, [$$]
    %define GLOBAL +r5-$$
%else
    %define GLOBAL
%endif
    LAST_MASK_LUT %1, eax, r0-(%1&1)*SIZEOF_DCTCOEF
%if %1==15
    shr     eax, 1
%elif %1==8
    and     eax, 0xff
%elif %1==4
    and     eax, 0xf
%endif
    xor     eax, (1<<%1)-1
    mov [r1+levelrun.mask], eax
%if %1==15
    add     eax, eax
%endif
%if %1 > 8
%if ARCH_X86_64
    mov     r4d, eax
    shr     r4d, 8
%else
    movzx   r4d, ah ; first 8 bits
%endif
%endif
    movzx   r2d, al ; second 8 bits
    shl     eax, 32-%1-(%1&1)
    LZCOUNT eax, eax, 0x1f
    mov     r3d, %1-1
    sub     r3d, eax
    mov [r1+levelrun.last], r3d
; Here we abuse pshufb, combined with a lookup table, to do a gather
; operation based on a bitmask. For example:
;
; dct 15-8 (input): 0  0  4  0  0 -2  1  0
; dct  7-0 (input): 0  0 -1  0  0  0  0 15
; bitmask 1:        0  0  1  0  0  1  1  0
; bitmask 2:        0  0  1  0  0  0  0  1
; gather 15-8:      4 -2  1 __ __ __ __ __
; gather  7-0:     -1 15 __ __ __ __ __ __
; levels (output):  4 -2  1 -1 15 __ __ __ __ __ __ __ __ __ __ __
;
; The overlapping, dependent stores almost surely cause a mess of
; forwarding issues, but it's still enormously faster.
%if %1 > 8
    movzx   eax, byte [popcnt_table+r4 GLOBAL]
    movzx   r3d, byte [popcnt_table+r2 GLOBAL]
%if mmsize==16
    movh      m3, [dct_coef_shuffle+r4*8 GLOBAL]
    movh      m2, [dct_coef_shuffle+r2*8 GLOBAL]
    mova      m4, [pw_256]
; Storing 8 bytes of shuffle constant and converting it (unpack + or)
; is neutral to slightly faster in local speed measurements, but it
; cuts the table size in half, which is surely a big cache win.
    punpcklbw m3, m3
    punpcklbw m2, m2
    por       m3, m4
    por       m2, m4
    pshufb    m1, m3
    pshufb    m0, m2
    mova [r1+levelrun.level], m1
; This obnoxious unaligned store messes with store forwarding and
; stalls the CPU to no end, but merging the two registers before
; storing requires a variable 128-bit shift. Emulating this does
; work, but requires a lot of ops and the gain is tiny and
; inconsistent, so we'll err on the side of fewer instructions.
    movu [r1+rax*2+levelrun.level], m0
%else ; mmsize==32
    movq     xm2, [dct_coef_shuffle+r4*8 GLOBAL]
    vinserti128 m2, m2, [dct_coef_shuffle+r2*8 GLOBAL], 1
    punpcklbw m2, m2
    por       m2, [pw_256]
    pshufb    m0, m2
    vextracti128 [r1+levelrun.level], m0, 1
    movu [r1+rax*2+levelrun.level], xm0
%endif
    add     eax, r3d
%else
    movzx   eax, byte [popcnt_table+r2 GLOBAL]
    movh m1, [dct_coef_shuffle+r2*8 GLOBAL]
    punpcklbw m1, m1
    por       m1, [pw_256]
    pshufb    m0, m1
    mova [r1+levelrun.level], m0
%endif
    RET
%endmacro

%if HIGH_BIT_DEPTH==0
INIT_MMX ssse3
COEFF_LEVELRUN_LUT 4
INIT_XMM ssse3
COEFF_LEVELRUN_LUT 8
COEFF_LEVELRUN_LUT 15
COEFF_LEVELRUN_LUT 16
INIT_MMX ssse3, lzcnt
COEFF_LEVELRUN_LUT 4
INIT_XMM ssse3, lzcnt
COEFF_LEVELRUN_LUT 8
COEFF_LEVELRUN_LUT 15
COEFF_LEVELRUN_LUT 16
INIT_XMM avx2
COEFF_LEVELRUN_LUT 15
COEFF_LEVELRUN_LUT 16
%endif
