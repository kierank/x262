/*****************************************************************************
 * mpeg2vlc.c : mpeg-2 vlc bitstream writing
 *****************************************************************************
 * Copyright (C) 2003-2010 x264 project
 *
 * Authors: Kieran Kunhya <kieran@kunhya.com>
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

/*****************************************************************************
 * x264_macroblock_write:
 *****************************************************************************/
void x262_macroblock_write_vlc( x264_t *h )
{
    bs_t *s = &h->out.bs;
    const int i_mb_type = h->mb.i_type;
    int cbp, quant;

#if RDO_SKIP_BS
    s->i_bits_encoded = 0;
#else
    const int i_mb_pos_start = bs_pos( s );
    int       i_mb_pos_tex = 0;
#endif

    quant = h->mb.i_last_qp != h->mb.i_qp;

    // macroblock modes
    if( i_mb_type == I_16x16 )
        bs_write_vlc( s, x262_i_mb_type[h->sh.i_type][quant] );
    else if( i_mb_type == P_8x8 )
    {


    }
    else //if( i_mb_type == B_8x8 )
    {

    }

    if( quant )
        bs_write( s, 5, h->mb.i_qp ); // quantizer_scale_code

    // forward mvs

    // backward mvs

#if !RDO_SKIP_BS
    i_mb_pos_tex = bs_pos( s );
    h->stat.frame.i_mv_bits += i_mb_pos_tex - i_mb_pos_start;
#endif

    cbp = h->mb.i_cbp_luma << 2 | h->mb.i_cbp_chroma;

    // coded block pattern (TODO: handle others)

    if( i_mb_type != I_16x16 && cbp )
        bs_write_vlc( s, x262_cbp[cbp] ); // coded_block_pattern_420

    for( int i = 0; i < 6; i++ )
    {
        // block()
        if( i_mb_type == I_16x16 )
        {
            h->dct.mpeg2_8x8[i][0] = 0;
            if( i < 4 )
            {
                // DC coefficient
                bs_write_vlc( s, x262_dc_luma_code[h->mb.i_dct_dc_size[i]] );
                if( h->mb.i_dct_dc_size[i] )
                    bs_write( s, h->mb.i_dct_dc_size[i], h->mb.i_dct_dc_diff[i] );
            }
            else
            {
                bs_write_vlc( s, x262_dc_chroma_code[h->mb.i_dct_dc_size[i]] );
                if( h->mb.i_dct_dc_size[i] )
                    bs_write( s, h->mb.i_dct_dc_size[i], h->mb.i_dct_dc_diff[i] );
            }
            bs_write_vlc( s, dct_vlcs[h->param.b_alt_intra_vlc][0][0] ); // end of block
        }
        else if( cbp & (1<<(5-i)) )
        {
        }
        else
            continue;
    }

#if !RDO_SKIP_BS
    h->stat.frame.i_tex_bits += bs_pos(s) - i_mb_pos_tex;
#endif
}
