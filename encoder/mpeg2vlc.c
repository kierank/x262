/*****************************************************************************
 * mpeg2vlc.c : mpeg-2 vlc bitstream writing
 *****************************************************************************
 * Copyright (C) 2003-2012 x264 project
 *
 * Authors: Kieran Kunhya <kieran@kunhya.com>
 *          Phillip Blucas <pblucas@gmail.com>
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

#include "common/common.h"

#ifndef RDO_SKIP_BS
#define RDO_SKIP_BS 0
#endif

#define bs_write_vlc(s,v) bs_write( s, (v).i_size, (v).i_bits )

/* Bit cost of coding one non-zero coefficient (run-level VLC + sign), matching
 * x264_write_dct_vlc_mpeg2 exactly. b_first is true for the first coded
 * coefficient in scan order (prev == -1), enabling the table B.14 special case
 * for an inter DC of magnitude 1. */
static ALWAYS_INLINE int mpeg2_coef_bits( int level, int run, int intra_tab, int inter, int b_first )
{
    int abs_level = abs( level );
    /* B.14 special case: inter DC magnitude 1 -> single '1' bit + sign */
    if( b_first && run == 0 && abs_level == 1 && inter )
        return 2;
    if( abs_level > 40 || run > 31 )
        return 24; /* escape: prefix + run + level */
    return dct_vlcs[intra_tab][abs_level][run].i_size;
}

#if !RDO_SKIP_BS
/* Composed scan permutations for the adaptive-scan bit counter: the block is
 * only available in the current scan's linear order at write time, so build
 * the other scan's linear order as other[k] = l[perm[k]], where
 * perm = inverse(cur_scan_to_flat) o other_scan_to_flat. */
static const uint8_t scan_perm_zigzag_to_alt[64] =
{
     0,  2,  3,  9,  1,  4,  5,  7,
     8, 11, 10, 20, 21, 35, 36, 34,
    22, 19, 18, 12,  6, 13, 14, 16,
    17, 24, 23, 33, 37, 48, 32, 38,
    47, 49, 25, 31, 15, 26, 27, 29,
    30, 40, 39, 46, 50, 57, 45, 51,
    56, 58, 41, 44, 28, 42, 43, 53,
    52, 55, 59, 62, 54, 60, 61, 63,
};
static const uint8_t scan_perm_alt_to_zigzag[64] =
{
     0,  4,  1,  2,  5,  6, 20,  7,
     8,  3, 10,  9, 19, 21, 22, 36,
    23, 24, 18, 17, 11, 12, 16, 26,
    25, 34, 37, 38, 52, 39, 40, 35,
    30, 27, 15, 13, 14, 28, 31, 42,
    41, 50, 53, 54, 51, 46, 43, 32,
    29, 33, 44, 47, 56, 55, 60, 57,
    48, 45, 49, 58, 61, 62, 59, 63,
};

/* AC bits x264_write_dct_vlc_mpeg2 would emit for l, without writing. */
static int mpeg2_dct_vlc_size( x264_t *h, dctcoef *l, int intra_tab )
{
    x264_run_level_t runlevel;
    const int inter = h->mb.i_type != I_16x16;
    int i_total = h->quantf.coeff_level_run[DCT_LUMA_8x8]( l, &runlevel ) - 1;
    uint64_t mask = runlevel.mask64;
    int prev = inter ? -1 : 0;
    int bits = 0;

    for( int i = i_total; i >= 0 && ( runlevel.last > 0 || inter ); i-- )
    {
        int pos = x264_ctz64( mask );
        mask &= mask - 1;
        bits += mpeg2_coef_bits( runlevel.level[i], pos - prev - 1, intra_tab, inter, i == i_total );
        prev = pos;
    }
    return bits;
}

/* Accumulate this block's AC bits under both scans for the per-picture
 * adaptive-scan decision. EOB, intra DC and MB overhead are scan-independent
 * and cancel out of the comparison. */
static void mpeg2_accum_alt_scan_bits( x264_t *h, dctcoef *l, int intra_tab )
{
    ALIGNED_ARRAY_64( dctcoef, other,[64] );
    int cur = h->fenc->b_alternate_scan;
    const uint8_t *perm = cur ? scan_perm_alt_to_zigzag : scan_perm_zigzag_to_alt;
    for( int i = 0; i < 64; i++ )
        other[i] = l[perm[i]];
    h->stat.frame.i_alt_scan_bits[cur]   += mpeg2_dct_vlc_size( h, l, intra_tab );
    h->stat.frame.i_alt_scan_bits[cur^1] += mpeg2_dct_vlc_size( h, other, intra_tab );
}

static void mpeg2_accum_intra_vlc_bits( x264_t *h, dctcoef *l )
{
    x264_run_level_t runlevel;
    int i_total = h->quantf.coeff_level_run[DCT_LUMA_8x8]( l, &runlevel ) - 1;
    uint64_t mask = runlevel.mask64;
    int prev = 0;
    int bits0 = dct_vlcs[0][0][0].i_size; /* EOB size for table 0 */
    int bits1 = dct_vlcs[1][0][0].i_size; /* EOB size for table 1 */

    for( int i = i_total; i >= 0 && runlevel.last > 0; i-- )
    {
        int pos = x264_ctz64( mask );
        mask &= mask - 1;
        int run = pos - prev - 1;
        prev = pos;
        int abs_level = abs( runlevel.level[i] );

        if( abs_level <= 40 && run <= 31 )
        {
            int sz0 = dct_vlcs[0][abs_level][run].i_size;
            int sz1 = dct_vlcs[1][abs_level][run].i_size;
            bits0 += sz0;
            bits1 += sz1;
        }
        else
        {
            bits0 += 24;
            bits1 += 24;
        }
    }
    h->stat.frame.i_intra_vlc_bits[0] += bits0;
    h->stat.frame.i_intra_vlc_bits[1] += bits1;
}
#endif

static void x264_write_dct_vlc_mpeg2( x264_t *h, dctcoef *l, int intra_tab )
{
    bs_t *s = &h->out.bs;
    x264_run_level_t runlevel;
    int i_total = 0;
    const int inter = h->mb.i_type != I_16x16;

#if !RDO_SKIP_BS
    if( h->mb.b_adaptive_scan )
        mpeg2_accum_alt_scan_bits( h, l, intra_tab );
    if( h->mb.b_adaptive_intra_vlc && !inter )
        mpeg2_accum_intra_vlc_bits( h, l );
#endif

    /* minus one because runlevel is zero-indexed and backwards */
    i_total = h->quantf.coeff_level_run[DCT_LUMA_8x8]( l, &runlevel ) - 1;
    uint64_t mask = runlevel.mask64;
    int prev = inter ? -1 : 0; // compensate for the DC coefficient set to zero

    for( int i = i_total; i >= 0 && ( runlevel.last > 0 || inter ); i-- )
    {
        int pos = x264_ctz64( mask );
        mask &= mask - 1;
        int run = pos - prev - 1;
        prev = pos;
        int abs_level = abs( runlevel.level[i] );
        if( abs_level <= 40 && run <= 31 )
        {
            vlc_large_t vlc = dct_vlcs[intra_tab][abs_level][run];
            int sz = vlc.i_size;
            if( sz != 24 )
            {
                /* special case in table B.14 for abs(DC) == 1 */
                if( i == i_total && run == 0 &&
                    ( runlevel.level[i] == 1 || runlevel.level[i] == -1 ) && inter )
                    bs_write1( s, 1 );
                else
                    bs_write( s, vlc.i_size - 1, vlc.i_bits ); /* i_size includes sign; write code only */
                bs_write1( s, runlevel.level[i] < 0 );
            }
            else
            {
                bs_write( s, 6, 0x01 ); // escape prefix
                bs_write( s, 6, run );
                bs_write( s, 12, runlevel.level[i] & ((1<<12)-1) ); // convert to 12-bit signed
            }
        }
        else
        {
            bs_write( s, 6, 0x01 ); // escape prefix
            bs_write( s, 6, run );
            bs_write( s, 12, runlevel.level[i] & ((1<<12)-1) ); // convert to 12-bit signed
        }
    }
}

static void x264_write_mv_vlc_mpeg2( x264_t *h, int mvd, int f_code )
{
    bs_t *s = &h->out.bs;
    int r_size = f_code - 1;
    int f = 1 << r_size;
    int low = -(f << 4);
    int high = -low - 1;
    int range =  f << 5;

    if( mvd > high )
        mvd -= range;
    else if( mvd < low  )
        mvd += range;

    int m_residual = abs( mvd ) + f - 1;
    int m_code = m_residual >> r_size;
    if( mvd < 0 )
        m_code = -m_code;
    bs_write_vlc( s, x264_motion_code[m_code + 16] ); // motion_code
    if( r_size && m_code )
        bs_write( s, r_size, m_residual & (f - 1) ); // motion_residual
}

void x264_macroblock_write_vlc_mpeg2( x264_t *h )
{
    bs_t *s = &h->out.bs;
    const int i_mb_type = h->mb.i_type;

#if RDO_SKIP_BS
    s->i_bits_encoded = 0;
#endif

    const int b_dual_prime = i_mb_type == P_DUAL_PRIME;
    int cbp420 = h->mb.i_cbp_luma << 2 | h->mb.i_cbp_chroma;
    int cbp = cbp420 << 2 | h->mb.i_cbp_chroma422;
    int coded = !!cbp;
    int quant = h->mb.i_last_qp != h->mb.i_qp && !MPEG2_SLICE_START;
    int mcoded = !!M32( h->mb.cache.mv[0][X264_SCAN8_0] );
    if( MB_INTERLACED )
        mcoded =  mcoded || (!!M32( h->mb.cache.mv[0][X264_SCAN8_0 + 2*8] ))
               || (h->mb.cache.ref[0][X264_SCAN8_0] != 0)
               || (h->mb.cache.ref[0][X264_SCAN8_0 + 2*8] != 1)
               || b_dual_prime;
    int mv_type = 0;

    /* must code a zero mv for macroblocks that cannot be (P|B)_SKIP */
    if( !cbp && !mcoded )
        mcoded = 1;

    /* can't use a quant macroblock_type when there are no blocks to code */
    if( quant && !coded )
    {
        quant = 0;
#if !RDO_SKIP_BS
        /* The real writer inherits the previous QP for a non-coded MB; the size-only
         * RD variant must not mutate i_qp, since RD runs multiple times per MB. */
        h->mb.i_qp = h->mb.i_last_qp;
#endif
    }

    // macroblock modes
    if( i_mb_type == I_16x16 )
        bs_write_vlc( s, x264_i_mb_type[h->sh.i_type][quant] );
    else if( i_mb_type == P_L0 || b_dual_prime )
    {
        /* dual-prime uses the same P macroblock_type VLC; only motion_type differs */
        bs_write_vlc( s, x264_p_mb_type[mcoded][coded][quant] );
        if( !mcoded )
            x264_reset_mv_predictor_mpeg2( h );
    }
    else
    {
        if( i_mb_type == B_L1_L1 )
            mv_type = 1;
        else if( i_mb_type == B_BI_BI )
            mv_type = 2;
        bs_write_vlc( s, x264_b_mb_type[mv_type][coded][quant] );
    }

    if( PARAM_INTERLACED || h->param.b_fake_interlaced )
    {
        if( ((i_mb_type == P_L0 || b_dual_prime) && mcoded) || (i_mb_type > P_L0 && !b_dual_prime) )
            bs_write( s, 2, b_dual_prime ? 3 : 2 - MB_INTERLACED ); // frame|field_motion_type (3 = dual-prime)
        if( coded )
            bs_write1( s, h->mb.b_field_dct ); // dct_type
    }

    if( quant )
        bs_write( s, 5, h->mb.i_qp ); // quantizer_scale_code

#if !RDO_SKIP_BS
    int i_mb_pos_mv = bs_pos( s );
#endif

    // write mvs
    if( ((i_mb_type == P_L0 || b_dual_prime) && mcoded) || (i_mb_type != P_L0 && !b_dual_prime && i_mb_type != I_16x16) )
    {
        if( b_dual_prime )
        {
            /* Dual-prime: one field MV in full, then dmvector[0]/dmvector[1]. No
             * motion_vertical_field_select is coded (each field's same-parity ref is
             * implicit). The coded MV lives in the list0 top-field cache slot. */
            int16_t *mv = h->mb.cache.mv[0][X264_SCAN8_0];
            x264_write_mv_vlc_mpeg2( h, (mv[0]>>1) - (h->mb.mvp[0][0][0]>>1),
                                     h->fenc->mv_fcode[0][0] );
            bs_write_vlc( s, x264_dmvector[h->mb.i_dmv[0] + 1] ); // dmvector[0]
            x264_write_mv_vlc_mpeg2( h, (mv[1]>>1) - (h->mb.mvp[0][0][1]>>2),
                                     h->fenc->mv_fcode[0][1] );
            bs_write_vlc( s, x264_dmvector[h->mb.i_dmv[1] + 1] ); // dmvector[1]
            // update predictors (only the coded MV; derived MVs have no predictor)
            h->mb.mvp[0][0][0] = h->mb.mvp[1][0][0] = mv[0];
            h->mb.mvp[0][0][1] = h->mb.mvp[1][0][1] = (mv[1] & ~1) * 2;
        }
        else if( MB_INTERLACED )
        {
            int mvcount = 2;
            mv_type = 0;

            if( i_mb_type == B_BI_BI )
                mvcount = 4;
            else if( i_mb_type == B_L1_L1 )
                mv_type = 1;

            for( int i = 0; i < mvcount; i+=2, mv_type++)
            {
                for( int j = 0; j < 2; j++ )
                {
                    bs_write(s,1,h->mb.cache.ref[mv_type][X264_SCAN8_0 + (2*8*j)]);

                    x264_write_mv_vlc_mpeg2( h, (h->mb.cache.mv[mv_type][X264_SCAN8_0 + (2*8*j)][0]>>1) - (h->mb.mvp[j][mv_type][0]>>1),
                                             h->fenc->mv_fcode[mv_type][0] );
                    x264_write_mv_vlc_mpeg2( h, (h->mb.cache.mv[mv_type][X264_SCAN8_0 + (2*8*j)][1]>>1) - (h->mb.mvp[j][mv_type][1]>>2),
                                             h->fenc->mv_fcode[mv_type][1] );
                    // update predictors
                    h->mb.mvp[j][mv_type][0] = (h->mb.cache.mv[mv_type][X264_SCAN8_0 + (2*8*j)][0]);
                    h->mb.mvp[j][mv_type][1] = (h->mb.cache.mv[mv_type][X264_SCAN8_0 + (2*8*j)][1] & ~1) * 2;
                }
            }
        }
        else
        {
            int mvcount = 1;

            mv_type = 0;
            if( i_mb_type == B_BI_BI )
                mvcount = 2;
            else if( i_mb_type == B_L1_L1 )
                mv_type = 1;

            for( int j = 0; j < mvcount; j++, mv_type++ )
            {
                x264_write_mv_vlc_mpeg2( h, ( h->mb.cache.mv[mv_type][x264_scan8[0]][0] - h->mb.mvp[0][mv_type][0] ) >> 1,
                                         h->fenc->mv_fcode[mv_type][0] );
                x264_write_mv_vlc_mpeg2( h, ( h->mb.cache.mv[mv_type][x264_scan8[0]][1] - h->mb.mvp[0][mv_type][1] ) >> 1,
                                         h->fenc->mv_fcode[mv_type][1] );
                // update predictors
                M32( h->mb.mvp[0][mv_type] ) = M32( h->mb.cache.mv[mv_type][X264_SCAN8_0] );
                M32( h->mb.mvp[1][mv_type] ) = M32( h->mb.cache.mv[mv_type][X264_SCAN8_0] );
            }
        }
    }

#if !RDO_SKIP_BS
    int i_mb_pos_tex = bs_pos( s );
    h->stat.frame.i_mv_bits += i_mb_pos_tex - i_mb_pos_mv;
#endif

    // block()
    int blockcount = CHROMA_FORMAT == CHROMA_420 ? 6 : 8;
    if( i_mb_type == I_16x16 )
    {
        for( int i = 0; i < blockcount; i++ )
        {
            h->dct.mpeg2_8x8[i][0] = 0;
            if( i < 4 )
                bs_write_vlc( s, x264_dc_luma_code[h->mb.i_dct_dc_size[i]] );
            else
                bs_write_vlc( s, x264_dc_chroma_code[h->mb.i_dct_dc_size[i]] );

            if( h->mb.i_dct_dc_size[i] )
                bs_write( s, h->mb.i_dct_dc_size[i], h->mb.i_dct_dc_diff[i] ); // DC
            x264_write_dct_vlc_mpeg2( h, h->dct.mpeg2_8x8[i], h->fenc->b_alt_intra_vlc ); // AC
            vlc_large_t _eob = dct_vlcs[h->fenc->b_alt_intra_vlc][0][0];
            bs_write( s, _eob.i_size, _eob.i_bits ); // end of block
        }
    }
    else if( cbp )
    {
        bs_write_vlc( s, x264_cbp[cbp420] ); // coded_block_pattern_420
        if( CHROMA_FORMAT == CHROMA_422 )
            bs_write( s, 2, cbp & 0x3 );     // coded_block_pattern_1

        for( int i = 0; i < 8; i++ )
        {
            if( cbp & (1<<(7-i)) )
            {
                x264_write_dct_vlc_mpeg2( h, h->dct.mpeg2_8x8[i], 0 ); // DC and AC
                bs_write( s, 2, 0x2 ); // end of block
            }
        }
    }

#if !RDO_SKIP_BS
    h->stat.frame.i_tex_bits += bs_pos(s) - i_mb_pos_tex;
#endif
}
