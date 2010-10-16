/*****************************************************************************
 * mpeg2vlc.c : mpeg-2 vlc tables
 *****************************************************************************
 * Copyright (C) 2003-2010 x264 project
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

#include "common.h"

const vlc_t x262_mb_addr_inc[34] =
{
    { 0x1, 1 },   /* str=1 */
    { 0x3, 3 },   /* str=011 */
    { 0x2, 3 },   /* str=010 */
    { 0x3, 4 },   /* str=0011 */
    { 0x2, 4 },   /* str=0010 */
    { 0x3, 5 },   /* str=00011 */
    { 0x2, 5 },   /* str=00010 */
    { 0x7, 7 },   /* str=0000111 */
    { 0x6, 7 },   /* str=0000110 */
    { 0xb, 8 },   /* str=00001011 */
    { 0xa, 8 },   /* str=00001010 */
    { 0x9, 8 },   /* str=00001001 */
    { 0x8, 8 },   /* str=00001000 */
    { 0x7, 8 },   /* str=00000111 */
    { 0x6, 8 },   /* str=00000110 */
    { 0x17, 10 }, /* str=0000010111 */
    { 0x16, 10 }, /* str=0000010110 */
    { 0x15, 10 }, /* str=0000010101 */
    { 0x14, 10 }, /* str=0000010100 */
    { 0x13, 10 }, /* str=0000010011 */
    { 0x12, 10 }, /* str=0000010010 */
    { 0x23, 11 }, /* str=00000100011 */
    { 0x22, 11 }, /* str=00000100010 */
    { 0x21, 11 }, /* str=00000100001 */
    { 0x20, 11 }, /* str=00000100000 */
    { 0x1f, 11 }, /* str=00000011111 */
    { 0x1e, 11 }, /* str=00000001110 */
    { 0x1d, 11 }, /* str=00000011101 */
    { 0x1c, 11 }, /* str=00000011100 */
    { 0x1b, 11 }, /* str=00000011011 */
    { 0x1a, 11 }, /* str=00000011010 */
    { 0x19, 11 }, /* str=00000011001 */
    { 0x18, 11 }, /* str=00000011000 */
    { 0x8, 11 },  /* escape */
};

const vlc_t x262_cbp[64] =
{
    { 0x1, 9 },  /* str=000000001 */
    { 0xb, 5 },  /* str=01011 */
    { 0x9, 5 },  /* str=01001 */
    { 0xd, 6 },  /* str=001101 */
    { 0xd, 4 },  /* str=1101 */
    { 0x17, 7 }, /* str=0010111 */
    { 0x13, 7 }, /* str=0010011 */
    { 0x1f, 8 }, /* str=00011111 */
    { 0xc, 4 },  /* str=1100 */
    { 0x16, 7 }, /* str=0010110 */
    { 0x12, 7 }, /* str=0010010 */
    { 0x1e, 8 }, /* str=00011110 */
    { 0x13, 5 }, /* str=10011 */
    { 0x1b, 8 }, /* str=00011011 */
    { 0x17, 8 }, /* str=00010111 */
    { 0x13, 8 }, /* str=00010011 */
    { 0xb, 4 },  /* str=1011 */
    { 0x15, 7 }, /* str=0010101 */
    { 0x11, 7 }, /* str=0010001 */
    { 0x1d, 8 }, /* str=00011101 */
    { 0x11, 5 }, /* str=1000 1 */
    { 0x19, 8 }, /* str=00011001 */
    { 0x15, 8 }, /* str=00010101 */
    { 0x11, 8 }, /* str=00010001 */
    { 0xf, 6 },  /* str=001111 */
    { 0xf, 8 },  /* str=00001111 */
    { 0xd, 8 },  /* str=00001101 */
    { 0x3, 9 },  /* str=000000011 */
    { 0xf, 5 },  /* str=01111 */
    { 0xb, 8 },  /* str=00001011 */
    { 0x7, 8 },  /* str=00000111 */
    { 0x7, 9 },  /* str=000000111 */
    { 0xa, 4 },  /* str=1010 */
    { 0x14, 7 }, /* str=0010100 */
    { 0x10, 7 }, /* str=0010000 */
    { 0x1c, 8 }, /* str=00011100 */
    { 0xe, 6 },  /* str=001110 */
    { 0xe, 8 },  /* str=00001110 */
    { 0xc, 8 },  /* str=00001100 */
    { 0x2, 9 },  /* str=000000010 */
    { 0x10, 5 }, /* str=10000 */
    { 0x18, 8 }, /* str=00011000 */
    { 0x14, 8 }, /* str=00010100 */
    { 0x10, 8 }, /* str=00010000 */
    { 0xe, 5 },  /* str=01110 */
    { 0xa, 8 },  /* str=00001010 */
    { 0x6, 8 },  /* str=00000110 */
    { 0x6, 9 },  /* str=000000110 */
    { 0x12, 5 }, /* str=10010 */
    { 0x1a, 8 }, /* str=00011010 */
    { 0x16, 8 }, /* str=00010110 */
    { 0x12, 8 }, /* str=00010010 */
    { 0xd, 5 },  /* str=01101 */
    { 0x9, 8 },  /* str=00001001 */
    { 0x5, 8 },  /* str=00000101 */
    { 0x5, 9 },  /* str=000000101 */
    { 0xc, 5 },  /* str=01100 */
    { 0x8, 8 },  /* str=00001000 */
    { 0x4, 8 },  /* str=00000100 */
    { 0x4, 9 },  /* str=000000100 */
    { 0x7, 3 },  /* str=111 */
    { 0xa, 5 },  /* str=01010 */
    { 0x8, 5 },  /* str=01000 */
    { 0xc, 6 },  /* str=001100 */
};

/* [frame_type][quant] */
const vlc_t x262_i_mb_type[3][2] =
{
    {
	{ 0x3, 5 }, /* str=00011 */
	{ 0x1, 6 }, /* str=000001 */
    },
    {
	{ 0x3, 5 }, /* str=00011 */
	{ 0x1, 6 }, /* str=000001 */
    },
    {
        { 0x1, 1 }, /* str=1 */
        { 0x1, 2 }, /* str=01 */
    },
};

/* [mc][coded][quant] */
const vlc_t x262_p_mb_type[2][2][2] =
{
    {
        {},
        {
            { 0x1, 2 }, /* str=01 */
            { 0x1, 5 }, /* str=00001 */
        },
    },
    {
        {
            { 0x1, 3 }, /* str=001 */
        },
        {
            { 0x1, 1 }, /* str=1 */
            { 0x2, 5 }, /* str=00010 */
        },
    },
};

/* [fwd/bwd/interp][coded][quant] */
const vlc_t x262_b_mb_type[3][2][2] =
{
    {
        {
            { 0x2, 4 }, /* str=0010 */
        },
        {
            { 0x3, 4 }, /* str=0011 */
            { 0x2, 6 }, /* str=000010 */
        },
    },
    {
        {
            { 0x2, 3 }, /* str=010 */
        },
        {
            { 0x3, 3 }, /* str=011 */
            { 0x3, 6 }, /* str=000011 */
        },
    },
    {
        {
            { 0x2, 2 }, /* str=10 */
        },
        {
            { 0x3, 2 }, /* str=11 */
            { 0x2, 5 }, /* str=00010 */
        },
    },
};

/* [code] */
const vlc_large_t x262_dc_lum_code[12] =
{
    { 0x4, 3 }, /* str=100 */
    { 0x0, 2 }, /* str=00 */
    { 0x1, 2 }, /* str=01 */
    { 0x5, 3 }, /* str=101 */
    { 0x6, 3 }, /* str=110 */
    { 0xe, 4 }, /* str=1110 */
    { 0x1e, 5 }, /* str=11110 */
    { 0x3e, 6 }, /* str=111110 */
    { 0x7e, 7 }, /* str=1111110 */
    { 0xfe, 8 }, /* str=11111110 */
    { 0x1fe, 9 }, /* str=111111110 */
    { 0x1ff, 9 }, /* str=111111111 */
};

/* [code] */
const vlc_large_t x262_dc_chroma_code[12] =
{
    { 0x0, 2 }, /* str=00 */
    { 0x1, 2 }, /* str=01 */
    { 0x2, 2 }, /* str=10 */
    { 0x6, 3 }, /* str=110 */
    { 0xe, 4 }, /* str=1110 */
    { 0x1e, 5 }, /* str=11110 */
    { 0x3e, 6 }, /* str=111110 */
    { 0x7e, 7 }, /* str=1111110 */
    { 0xfe, 8 }, /* str=11111110 */
    { 0x1fe, 9 }, /* str=111111110 */
    { 0x3fe, 10 }, /* str=1111111110 */
    { 0x3ff, 10 }, /* str=1111111111 */
};
