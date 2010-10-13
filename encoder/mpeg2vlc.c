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

#if RDO_SKIP_BS
    s->i_bits_encoded = 0;
#else
    const int i_mb_pos_start = bs_pos( s );
    int       i_mb_pos_tex;
#endif

    // macroblock modes
    if( i_mb_type == I_16x16 )
    {

    }
    else if( i_mb_type == P_8x8 )
    {

    }
    else //if( i_mb_type == B_8x8 )
    {

    }

    // forward mvs

    // backward mvs

#if !RDO_SKIP_BS
    i_mb_pos_tex = bs_pos( s );
    h->stat.frame.i_mv_bits += i_mb_pos_tex - i_mb_pos_start;
#endif

    // coded block pattern

    // block()

#if !RDO_SKIP_BS
    h->stat.frame.i_tex_bits += bs_pos(s) - i_mb_pos_tex;
#endif


}
