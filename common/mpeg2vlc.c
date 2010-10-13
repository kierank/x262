/*****************************************************************************
 * mpeg2vlc.c : mpeg-2 vlc tables
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

#include "common.h"

const vlc_t x262_mb_addr_inc[34] =
{
    { 0x1, 1 }, /* str=1 */
    { 0x3, 3 }, /* str=011 */
    { 0x2, 3 }, /* str=010 */
    { 0x3, 4 }, /* str=0011 */
    { 0x2, 4 }, /* str=0010 */
    { 0x3, 5 }, /* str=00011 */
    { 0x2, 5 }, /* str=00010 */
    { 0x7, 7 }, /* str=0000111 */
    { 0x6, 7 }, /* str=0000110 */
    { 0xb, 8 }, /* str=00001011 */
    { 0xa, 8 }, /* str=00001010 */
    { 0x9, 8 }, /* str=00001001 */
    { 0x8, 8 }, /* str=00001000 */
    { 0x7, 8 }, /* str=00000111 */
    { 0x6, 8 }, /* str=00000110 */
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

const vlc_t x262_i_frame_mb_type[2]
{
    { 0x1, 1 }, /* str=1 */
    { 0x1, 2 }, /* str=01 */
};
