/*****************************************************************************
 * quant.h: quantization and level-run
 *****************************************************************************
 * Copyright (C) 2005-2025 x264 project
 *
 * Authors: Loren Merritt <lorenm@u.washington.edu>
 *          Fiona Glaser <fiona@x264.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02111, USA.
 *
 * This program is also available under a commercial proprietary license.
 * For more information, contact us at licensing@x264.com.
 *****************************************************************************/

#ifndef X264_QUANT_H
#define X264_QUANT_H

#if HAVE_MPEG2
/* Context for the MPEG-2 trellis DP kernel. One pointer arg keeps the
 * C-to-asm boundary cheap (no register/stack marshalling of 15+ operands);
 * the asm reads fields at fixed offsets, so field order is ABI — append only.
 * All tables are built by the caller (x264_quant_8x8_trellis_mpeg2); the
 * kernel runs the predecessor DP over the candidate list and the terminal
 * scan, writes back[]/lev[] (indexed by scan position), and returns the scan
 * position of the last kept coefficient (first-1 = none kept). */
typedef struct
{
    const int *n;                  /* candidate magnitudes, flat-indexed */
    const int64_t *dist_zero;      /* candidate distortions, flat-indexed */
    const int64_t *dist_n;
    const int64_t *dist_nm1;
    const uint8_t *scan;           /* scan position -> flat position */
    const uint8_t *list;           /* kept-candidate scan positions, ascending */
    int cnt;                       /* list entries; caller handles cnt <= 1 */
    int first;                     /* 1 intra (DC excluded), 0 inter */
    int inter;
    int64_t lambda;
    int64_t esc_lam;               /* escape-coded (run,level) rate * lambda */
    const int64_t (*rate_lam)[32]; /* per-level rate rows, run 0..31 */
    int max_lev;                   /* highest valid rate_lam row (<= 40) */
    const int64_t *esc_row;        /* all-esc_lam row; valid iff a level > max_lev occurs */
    int *back;                     /* out: predecessor scan pos per kept state */
    int *lev;                      /* out: chosen magnitude per kept state */
} x264_trellis_dp_ctx_t;
#endif

typedef struct
{
    int (*quant_8x8)  ( dctcoef dct[64], udctcoef mf[64], udctcoef bias[64] );
    int (*quant_4x4)  ( dctcoef dct[16], udctcoef mf[16], udctcoef bias[16] );
    int (*quant_4x4x4)( dctcoef dct[4][16], udctcoef mf[16], udctcoef bias[16] );
    int (*quant_4x4_dc)( dctcoef dct[16], int mf, int bias );
    int (*quant_2x2_dc)( dctcoef dct[4], int mf, int bias );

    void (*dequant_8x8)( dctcoef dct[64], int dequant_mf[6][64], int i_qp );
    void (*dequant_4x4)( dctcoef dct[16], int dequant_mf[6][16], int i_qp );
    void (*dequant_4x4_dc)( dctcoef dct[16], int dequant_mf[6][16], int i_qp );

    void (*idct_dequant_2x4_dc)( dctcoef dct[8], dctcoef dct4x4[8][16], int dequant_mf[6][16], int i_qp );
    void (*idct_dequant_2x4_dconly)( dctcoef dct[8], int dequant_mf[6][16], int i_qp );

    int (*optimize_chroma_2x2_dc)( dctcoef dct[4], int dequant_mf );
    int (*optimize_chroma_2x4_dc)( dctcoef dct[8], int dequant_mf );

    void (*denoise_dct)( dctcoef *dct, uint32_t *sum, udctcoef *offset, int size );

    int (*decimate_score15)( dctcoef *dct );
    int (*decimate_score16)( dctcoef *dct );
    int (*decimate_score64)( dctcoef *dct );
    int (*coeff_last[14])( dctcoef *dct );
    int (*coeff_last4)( dctcoef *dct );
    int (*coeff_last8)( dctcoef *dct );
    int (*coeff_level_run[13])( dctcoef *dct, x264_run_level_t *runlevel );
    int (*coeff_level_run4)( dctcoef *dct, x264_run_level_t *runlevel );
    int (*coeff_level_run8)( dctcoef *dct, x264_run_level_t *runlevel );

#if HAVE_MPEG2
    void (*dequant_mpeg2_intra)( dctcoef dct[64], int dequant_mf[64], int precision );
    void (*dequant_mpeg2_inter)( dctcoef dct[64], int dequant_mf[64] );
    void (*coeff_clip_mpeg2)( dctcoef dct[64] );
    /* MPEG-2 trellis per-level rate row: dst[run] = bits[run]*lambda, run 0..31. */
    void (*trellis_rate_build_mpeg2)( int64_t *dst, const uint16_t *bits, int64_t lambda );
    /* MPEG-2 trellis per-position setup: fills n/sgn[0..63] and returns nonzero
     * iff any position quantizes to a nonzero magnitude (OR over all 64 flat
     * positions). The dist arrays are filled only in that case; on a zero
     * return they are untouched/undefined. */
    int (*trellis_setup_mpeg2)( int *n, int *sgn, int64_t *dist_zero, int64_t *dist_n,
                                int64_t *dist_nm1, const dctcoef *dct, const udctcoef *quant_mf,
                                const udctcoef *quant_bias0, const int *dequant_mf, int intra );
    /* MPEG-2 trellis DP over the candidate list (see x264_trellis_dp_ctx_t). */
    int (*trellis_dp_mpeg2)( const x264_trellis_dp_ctx_t *t );
    /* MPEG-2 trellis: scan-order list of the positions s (0..63) with
     * n[scan[s]] != 0; returns the count. Entries past the count are
     * undefined. */
    int (*trellis_list_mpeg2)( uint8_t *list, const int *n, const uint8_t *scan );
#endif

#define TRELLIS_PARAMS const int *unquant_mf, const uint8_t *zigzag, int lambda2,\
                       int last_nnz, dctcoef *coefs, dctcoef *quant_coefs, dctcoef *dct,\
                       uint8_t *cabac_state_sig, uint8_t *cabac_state_last,\
                       uint64_t level_state0, uint16_t level_state1
    int (*trellis_cabac_4x4)( TRELLIS_PARAMS, int b_ac );
    int (*trellis_cabac_8x8)( TRELLIS_PARAMS, int b_interlaced );
    int (*trellis_cabac_4x4_psy)( TRELLIS_PARAMS, int b_ac, dctcoef *fenc_dct, int psy_trellis );
    int (*trellis_cabac_8x8_psy)( TRELLIS_PARAMS, int b_interlaced, dctcoef *fenc_dct, int psy_trellis );
    int (*trellis_cabac_dc)( TRELLIS_PARAMS, int num_coefs );
    int (*trellis_cabac_chroma_422_dc)( TRELLIS_PARAMS );
} x264_quant_function_t;

#define x264_quant_init x264_template(quant_init)
void x264_quant_init( x264_t *h, uint32_t cpu, x264_quant_function_t *pf );

#endif
