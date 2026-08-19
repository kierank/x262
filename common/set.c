/*****************************************************************************
 * set.c: quantization init
 *****************************************************************************
 * Copyright (C) 2005-2025 x264 project
 *
 * Authors: Loren Merritt <lorenm@u.washington.edu>
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

#define SHIFT(x,s) ((s)<=0 ? (x)<<-(s) : ((x)+(1<<((s)-1)))>>(s))
#define DIV(n,d) (((n) + ((d)>>1)) / (d))

static const uint8_t dequant4_scale[6][3] =
{
    { 10, 13, 16 },
    { 11, 14, 18 },
    { 13, 16, 20 },
    { 14, 18, 23 },
    { 16, 20, 25 },
    { 18, 23, 29 }
};
static const uint16_t quant4_scale[6][3] =
{
    { 13107, 8066, 5243 },
    { 11916, 7490, 4660 },
    { 10082, 6554, 4194 },
    {  9362, 5825, 3647 },
    {  8192, 5243, 3355 },
    {  7282, 4559, 2893 },
};

static const uint8_t quant8_scan[16] =
{
    0,3,4,3, 3,1,5,1, 4,5,2,5, 3,1,5,1
};
static const uint8_t dequant8_scale[6][6] =
{
    { 20, 18, 32, 19, 25, 24 },
    { 22, 19, 35, 21, 28, 26 },
    { 26, 23, 42, 24, 33, 31 },
    { 28, 25, 45, 26, 35, 33 },
    { 32, 28, 51, 30, 40, 38 },
    { 36, 32, 58, 34, 46, 43 },
};
static const uint16_t quant8_scale[6][6] =
{
    { 13107, 11428, 20972, 12222, 16777, 15481 },
    { 11916, 10826, 19174, 11058, 14980, 14290 },
    { 10082,  8943, 15978,  9675, 12710, 11985 },
    {  9362,  8228, 14913,  8931, 11984, 11259 },
    {  8192,  7346, 13159,  7740, 10486,  9777 },
    {  7282,  6428, 11570,  6830,  9118,  8640 }
};

#if HAVE_MPEG2 && !HIGH_BIT_DEPTH
static const uint8_t qscale_linear_mpeg2[32] =
{
      0,   2,   4,   6,   8,  10,  12,  14,
     16,  18,  20,  22,  24,  26,  28,  30,
     32,  34,  36,  38,  40,  42,  44,  46,
     48,  50,  52,  54,  56,  58,  60,  62
};
static const uint8_t qscale_nonlinear_mpeg2[32] =
{
      0,   1,   2,   3,   4,   5,   6,   7,
      8,  10,  12,  14,  16,  18,  20,  22,
     24,  28,  32,  36,  40,  44,  48,  52,
     56,  64,  72,  80,  88,  96, 104, 112
};
static const uint8_t * const x264_qscale_mpeg2[2] =
{
    qscale_linear_mpeg2, qscale_nonlinear_mpeg2
};
/* Per-frame matrix scale set; index MPEG2_CQM_CENTER_IDENTITY is S=1.0 (base
 * matrix). S<1 subdivides the coarse bottom of the 1-31 grid; S up to 2.5 reaches
 * the >31 "fake QP" range (qp 49 needs S~2.3: grid[31]=112, target there ~256). */
#define MPEG2_CQM_CENTER_COUNT 10
static const float x264_mpeg2_cqm_center_scale[MPEG2_CQM_CENTER_COUNT] =
    { 0.200f, 0.350f, 0.500f, 0.667f, 0.833f, 1.000f, 1.250f, 1.500f, 2.000f, 2.500f };
/* Recenter target (code 12 = qscale 16), and the local grid step above which the
 * grid is coarse enough to be worth recentering (the step at the optimum). */
#define MPEG2_CQM_CENTER_OPT 12
#define MPEG2_CQM_CENTER_MIN_STEP 0.115f
#define MPEG2_CQM_CENTER_SWITCH_COST 4
#endif /* HAVE_MPEG2 && !HIGH_BIT_DEPTH */

int x264_cqm_init( x264_t *h )
{
    int def_quant4[6][16];
    int def_quant8[6][64];
    int def_dequant4[6][16];
    int def_dequant8[6][64];
    int quant4_mf[4][6][16];
    int quant8_mf[4][6][64];
    int deadzone[4] = { 32 - h->param.analyse.i_luma_deadzone[1],
                        32 - h->param.analyse.i_luma_deadzone[0],
                        32 - 11, 32 - 21 };
    int max_qp_err = -1;
    int max_chroma_qp_err = -1;
    int min_qp_err = QP_MAX+1;
    int num_8x8_lists = h->sps->i_chroma_format_idc == CHROMA_444 ? 4
                      : h->param.analyse.b_transform_8x8 ? 2 : 0; /* Checkasm may segfault if optimized out by --chroma-format */

#define CQM_ALLOC( w, count )\
    for( int i = 0; i < count; i++ )\
    {\
        int size = w*w;\
        int start = w == 8 ? 4 : 0;\
        int j;\
        for( j = 0; j < i; j++ )\
            if( !memcmp( h->sps->scaling_list[i+start], h->sps->scaling_list[j+start], size*sizeof(uint8_t) ) )\
                break;\
        if( j < i )\
        {\
            h->  quant##w##_mf[i] = h->  quant##w##_mf[j];\
            h->dequant##w##_mf[i] = h->dequant##w##_mf[j];\
            h->unquant##w##_mf[i] = h->unquant##w##_mf[j];\
        }\
        else\
        {\
            CHECKED_MALLOC( h->  quant##w##_mf[i], (QP_MAX_SPEC+1)*size*sizeof(udctcoef) );\
            CHECKED_MALLOC( h->dequant##w##_mf[i],  6*size*sizeof(int) );\
            CHECKED_MALLOC( h->unquant##w##_mf[i], (QP_MAX_SPEC+1)*size*sizeof(int) );\
        }\
        for( j = 0; j < i; j++ )\
            if( deadzone[j] == deadzone[i] &&\
                !memcmp( h->sps->scaling_list[i+start], h->sps->scaling_list[j+start], size*sizeof(uint8_t) ) )\
                break;\
        if( j < i )\
        {\
            h->quant##w##_bias[i] = h->quant##w##_bias[j];\
            h->quant##w##_bias0[i] = h->quant##w##_bias0[j];\
        }\
        else\
        {\
            CHECKED_MALLOC( h->quant##w##_bias[i], (QP_MAX_SPEC+1)*size*sizeof(udctcoef) );\
            CHECKED_MALLOC( h->quant##w##_bias0[i], (QP_MAX_SPEC+1)*size*sizeof(udctcoef) );\
        }\
    }

    CQM_ALLOC( 4, 4 )
    CQM_ALLOC( 8, num_8x8_lists )

    for( int q = 0; q < 6; q++ )
    {
        for( int i = 0; i < 16; i++ )
        {
            int j = (i&1) + ((i>>2)&1);
            def_dequant4[q][i] = dequant4_scale[q][j];
            def_quant4[q][i]   =   quant4_scale[q][j];
        }
        for( int i = 0; i < 64; i++ )
        {
            int j = quant8_scan[((i>>1)&12) | (i&3)];
            def_dequant8[q][i] = dequant8_scale[q][j];
            def_quant8[q][i]   =   quant8_scale[q][j];
        }
    }

    for( int q = 0; q < 6; q++ )
    {
        for( int i_list = 0; i_list < 4; i_list++ )
            for( int i = 0; i < 16; i++ )
            {
                h->dequant4_mf[i_list][q][i] = def_dequant4[q][i] * h->sps->scaling_list[i_list][i];
                     quant4_mf[i_list][q][i] = DIV(def_quant4[q][i] * 16, h->sps->scaling_list[i_list][i]);
            }
        for( int i_list = 0; i_list < num_8x8_lists; i_list++ )
            for( int i = 0; i < 64; i++ )
            {
                h->dequant8_mf[i_list][q][i] = def_dequant8[q][i] * h->sps->scaling_list[4+i_list][i];
                     quant8_mf[i_list][q][i] = DIV(def_quant8[q][i] * 16, h->sps->scaling_list[4+i_list][i]);
            }
    }

#define MAX_MF X264_MIN( 0xffff, (1 << (25 - BIT_DEPTH)) - 1 )

    for( int q = 0; q <= QP_MAX_SPEC; q++ )
    {
        int j;
        for( int i_list = 0; i_list < 4; i_list++ )
            for( int i = 0; i < 16; i++ )
            {
                h->unquant4_mf[i_list][q][i] = (1ULL << (q/6 + 15 + 8)) / quant4_mf[i_list][q%6][i];
                j = SHIFT(quant4_mf[i_list][q%6][i], q/6 - 1);
                h->quant4_mf[i_list][q][i] = (uint16_t)j;
                if( !j )
                {
                    min_qp_err = X264_MIN( min_qp_err, q );
                    continue;
                }
                // round to nearest, unless that would cause the deadzone to be negative
                h->quant4_bias[i_list][q][i] = X264_MIN( DIV(deadzone[i_list]<<10, j), (1<<15)/j );
                h->quant4_bias0[i_list][q][i] = (1<<15)/j;
                if( j > MAX_MF && q > max_qp_err && (i_list == CQM_4IY || i_list == CQM_4PY) )
                    max_qp_err = q;
                if( j > MAX_MF && q > max_chroma_qp_err && (i_list == CQM_4IC || i_list == CQM_4PC) )
                    max_chroma_qp_err = q;
            }
        if( h->param.analyse.b_transform_8x8 )
            for( int i_list = 0; i_list < num_8x8_lists; i_list++ )
                for( int i = 0; i < 64; i++ )
                {
                    h->unquant8_mf[i_list][q][i] = (1ULL << (q/6 + 16 + 8)) / quant8_mf[i_list][q%6][i];
                    j = SHIFT(quant8_mf[i_list][q%6][i], q/6);
                    h->quant8_mf[i_list][q][i] = (uint16_t)j;

                    if( !j )
                    {
                        min_qp_err = X264_MIN( min_qp_err, q );
                        continue;
                    }
                    h->quant8_bias[i_list][q][i] = X264_MIN( DIV(deadzone[i_list]<<10, j), (1<<15)/j );
                    h->quant8_bias0[i_list][q][i] = (1<<15)/j;
                    if( j > MAX_MF && q > max_qp_err && (i_list == CQM_8IY || i_list == CQM_8PY) )
                        max_qp_err = q;
                    if( j > MAX_MF && q > max_chroma_qp_err && (i_list == CQM_8IC || i_list == CQM_8PC) )
                        max_chroma_qp_err = q;
                }
    }

    /* Emergency mode denoising. */
    x264_emms();
    CHECKED_MALLOC( h->nr_offset_emergency, sizeof(*h->nr_offset_emergency)*(QP_MAX-QP_MAX_SPEC) );
    for( int q = 0; q < QP_MAX - QP_MAX_SPEC; q++ )
        for( int cat = 0; cat < 3 + CHROMA444; cat++ )
        {
            int dct8x8 = cat&1;
            if( !h->param.analyse.b_transform_8x8 && dct8x8 )
                continue;

            int size = dct8x8 ? 64 : 16;
            udctcoef *nr_offset = h->nr_offset_emergency[q][cat];
            /* Denoise chroma first (due to h264's chroma QP offset), then luma, then DC. */
            int dc_threshold =    (QP_MAX-QP_MAX_SPEC)*2/3;
            int luma_threshold =  (QP_MAX-QP_MAX_SPEC)*2/3;
            int chroma_threshold = 0;

            for( int i = 0; i < size; i++ )
            {
                int max = (1 << (7 + BIT_DEPTH)) - 1;
                /* True "emergency mode": remove all DCT coefficients */
                if( q == QP_MAX - QP_MAX_SPEC - 1 )
                {
                    nr_offset[i] = max;
                    continue;
                }

                int thresh = i == 0 ? dc_threshold : cat >= 2 ? chroma_threshold : luma_threshold;
                if( q < thresh )
                {
                    nr_offset[i] = 0;
                    continue;
                }
                double pos = (double)(q-thresh+1) / (QP_MAX - QP_MAX_SPEC - thresh);

                /* XXX: this math is largely tuned for /dev/random input. */
                double start = dct8x8 ? h->unquant8_mf[CQM_8PY][QP_MAX_SPEC][i]
                                      : h->unquant4_mf[CQM_4PY][QP_MAX_SPEC][i];
                /* Formula chosen as an exponential scale to vaguely mimic the effects
                 * of a higher quantizer. */
                double bias = (pow( 2, pos*(QP_MAX - QP_MAX_SPEC)/10. )*0.003-0.003) * start;
                nr_offset[i] = X264_MIN( bias + 0.5, max );
            }
        }

    if( !h->mb.b_lossless )
    {
        while( h->chroma_qp_table[SPEC_QP(h->param.rc.i_qp_min)] <= max_chroma_qp_err )
            h->param.rc.i_qp_min++;
        if( min_qp_err <= h->param.rc.i_qp_max )
            h->param.rc.i_qp_max = min_qp_err-1;
        if( max_qp_err >= h->param.rc.i_qp_min )
            h->param.rc.i_qp_min = max_qp_err+1;
        /* If long level-codes aren't allowed, we need to allow QP high enough to avoid them. */
        if( !h->param.b_cabac && h->sps->i_profile_idc < PROFILE_HIGH )
            while( h->chroma_qp_table[SPEC_QP(h->param.rc.i_qp_max)] <= 12 || h->param.rc.i_qp_max <= 12 )
                h->param.rc.i_qp_max++;
        if( h->param.rc.i_qp_min > h->param.rc.i_qp_max )
        {
            x264_log( h, X264_LOG_ERROR, "Impossible QP constraints for CQM (min=%d, max=%d)\n", h->param.rc.i_qp_min, h->param.rc.i_qp_max );
            return -1;
        }
    }
    return 0;
fail:
    x264_cqm_delete( h );
    return -1;
}

#if HAVE_MPEG2 && !HIGH_BIT_DEPTH
/* Continues past code 31 into the fake-QP range on each table's own slope;
 * clipping there would cap RC's B/I planning at the rail. */
float x264_mpeg2_grid_qscale( x264_t *h, float code )
{
    const uint8_t *grid = x264_qscale_mpeg2[h->param.b_nonlinear_quant];
    float c = x264_clip3f( code, 1.0f, (float)QP_MAX_MPEG2 );
    if( c > QP_MAX_SPEC_MPEG2 )
        return h->param.b_nonlinear_quant
             ? grid[QP_MAX_SPEC_MPEG2] * powf( 2.0f, ( c - QP_MAX_SPEC_MPEG2 ) / 8.0f )
             : grid[QP_MAX_SPEC_MPEG2] + 2.0f * ( c - QP_MAX_SPEC_MPEG2 );
    int lo = X264_MIN( (int)c, QP_MAX_SPEC_MPEG2-1 );
    return grid[lo] + (c - lo) * (float)( grid[lo+1] - grid[lo] );
}

float x264_mpeg2_grid_code( x264_t *h, float qscale )
{
    const uint8_t *grid = x264_qscale_mpeg2[h->param.b_nonlinear_quant];
    if( qscale <= grid[1] )
        return 1.0f;
    if( qscale > grid[QP_MAX_SPEC_MPEG2] )
    {
        float c = h->param.b_nonlinear_quant
                ? QP_MAX_SPEC_MPEG2 + 8.0f * log2f( qscale / grid[QP_MAX_SPEC_MPEG2] )
                : QP_MAX_SPEC_MPEG2 + ( qscale - grid[QP_MAX_SPEC_MPEG2] ) / 2.0f;
        return X264_MIN( c, (float)QP_MAX_MPEG2 );
    }
    for( int q = 1; q < QP_MAX_SPEC_MPEG2; q++ )
        if( qscale < grid[q+1] )
            return q + ( qscale - grid[q] ) / (float)( grid[q+1] - grid[q] );
    return (float)QP_MAX_SPEC_MPEG2;
}

/* Pure selection: pick the (matrix index k, grid code best_qp) whose effective
 * qscale grid[best_qp]*S_k best matches the continuous quant RC asked for (qpm),
 * plus the grid-only code (*pgrid_qp) RC would land on with no matrix change.
 * No state mutation, so ratecontrol can call this to learn centering's effect on
 * the effective quant BEFORE the decision is committed. Returns best_qp. */
static float mpeg2_interp_qscale( x264_t *h, float qpm )
{
    const uint8_t *qscale = x264_qscale_mpeg2[h->param.b_nonlinear_quant];
    if( qpm < 1.0f )
        return (float)qscale[1] * qpm;
    return x264_mpeg2_grid_qscale( h, qpm );
}

static int mpeg2_cqm_center_select( x264_t *h, float qpm, int emitted,
                                    float *pS, int *pk, int *pgrid_qp, float *ptarget )
{
    const uint8_t *qscale = x264_qscale_mpeg2[h->param.b_nonlinear_quant];
    float target_qscale = mpeg2_interp_qscale( h, qpm );

    float inv_target = 1.0f / X264_MAX( target_qscale, 1.0f );

    /* Grid-only precision: the best relative qscale error reachable with no
     * matrix change (S=1.0). This is the bar a scaled matrix must beat. */
    int grid_qp = 1;
    float grid_err = 1e10f;
    for( int q = 1; q <= QP_MAX_SPEC_MPEG2; q++ )
    {
        float err = fabsf( (float)qscale[q] * 1.0f - target_qscale ) * inv_target;
        if( err < grid_err ) { grid_err = err; grid_qp = q; }
    }

    int best_k = MPEG2_CQM_CENTER_IDENTITY, best_qp = grid_qp;

    /* Recenter toward the optimum code only where the grid is locally coarse (its
     * step resets after each octave) and above the rail; pick the (scale,code) whose
     * effective qscale grid[q]*S matches the target and is nearest the optimum. */
    float local_step = grid_qp < QP_MAX_SPEC_MPEG2
                     ? (float)( qscale[grid_qp+1] - qscale[grid_qp] ) / (float)qscale[grid_qp]
                     : 0.0f;
    if( h->sh.i_type == SLICE_TYPE_B )
    {
        float S = x264_mpeg2_cqm_center_scale[emitted];
        float best_err = 1e30f;
        for( int q = 1; q <= QP_MAX_SPEC_MPEG2; q++ )
        {
            float err = fabsf( (float)qscale[q] * S - target_qscale ) * inv_target;
            if( err < best_err ) { best_err = err; best_qp = q; best_k = emitted; }
        }
    }
    else if( target_qscale >= (float)qscale[2] && local_step > MPEG2_CQM_CENTER_MIN_STEP )
    {
        int best_dist = 1<<30;
        for( int k = 0; k < h->i_mpeg2_cqm_center_count; k++ )
        {
            float S = x264_mpeg2_cqm_center_scale[k];
            int switch_cost = k != emitted ? MPEG2_CQM_CENTER_SWITCH_COST : 0;
            for( int q = 1; q <= QP_MAX_SPEC_MPEG2; q++ )
            {
                float err = fabsf( (float)qscale[q] * S - target_qscale ) * inv_target;
                if( err > 0.06f ) continue;
                int dist = abs( q - MPEG2_CQM_CENTER_OPT ) + switch_cost;
                if( dist < best_dist ) { best_dist = dist; best_qp = q; best_k = k; }
            }
        }
    }

    *pk = best_k;
    *pS = x264_mpeg2_cqm_center_scale[best_k];
    *pgrid_qp = grid_qp;
    *ptarget = target_qscale;
    return best_qp;
}

float x264_mpeg2_cqm_center_scale_get( x264_t *h )
{
    return x264_mpeg2_cqm_center_scale[h->i_mpeg2_cqm_center_idx];
}


/* Pick the grid code q so grid[q]*S best matches the quant the MB asked for, so the
 * matrix scale S leaves the effective per-MB quant unchanged. */
int x264_mpeg2_cqm_center_mb_code( x264_t *h, float qp )
{
    const uint8_t *grid = x264_qscale_mpeg2[h->param.b_nonlinear_quant];
    float S = x264_mpeg2_cqm_center_scale[h->i_mpeg2_cqm_center_idx];
    int lo = x264_clip3( (int)qp, 1, QP_MAX_SPEC_MPEG2-1 );
    float want = qp < 1.f ? (float)grid[1] : grid[lo] + (qp-lo)*(grid[lo+1]-grid[lo]);
    float target = want / X264_MAX( S, 1e-3f );
    int best = 1; float berr = 1e30f;
    for( int q = 1; q <= QP_MAX_SPEC_MPEG2; q++ )
    {
        float e = fabsf( (float)grid[q] - target );
        if( e < berr ) { berr = e; best = q; }
    }
    return best;
}

/* Unit-free qscale ratio centering applies for this qpm: the effective dequant
 * step (grid[best_qp]*S) over the smooth interpolated target qscale (the qp2qscale
 * curve RC rides), NOT over the jumpy grid-only code. 1.0 when inactive or k=3. */
float x264_mpeg2_cqm_center_ratio( x264_t *h, float qpm )
{
    if( !h->param.b_cqm_recenter || h->i_mpeg2_cqm_center_count < 2 )
        return 1.0f;
    const uint8_t *grid = x264_qscale_mpeg2[h->param.b_nonlinear_quant];
    float S, target; int k, grid_qp;
    int best_qp = mpeg2_cqm_center_select( h, qpm, h->i_mpeg2_cqm_center_idx_emitted, &S, &k, &grid_qp, &target );
    return ( (float)grid[best_qp] * S ) / X264_MAX( target, 1.0f );
}

/* RC prediction hook: scale RC's qscale by centering's ratio so the bit estimate
 * matches the quant the encoder will actually code at. */
float x264_mpeg2_cqm_center_predict_qscale( x264_t *h, float qpm, float qscale_in )
{
    return qscale_in * x264_mpeg2_cqm_center_ratio( h, qpm );
}

/* Must search only the committed scale (what x264_ratecontrol_mb_qp emits);
 * a fresh selection could land on a different matrix once qpm drifts. */
float x264_mpeg2_cqm_center_committed_ratio( x264_t *h, float qpm )
{
    if( h->i_mpeg2_cqm_center_idx == MPEG2_CQM_CENTER_IDENTITY )
        return 1.0f;
    const uint8_t *qscale = x264_qscale_mpeg2[h->param.b_nonlinear_quant];
    float S = x264_mpeg2_cqm_center_scale[h->i_mpeg2_cqm_center_idx];
    float target = mpeg2_interp_qscale( h, qpm );
    int best = 1;
    float berr = 1e30f;
    for( int q = 1; q <= QP_MAX_SPEC_MPEG2; q++ )
    {
        float e = fabsf( (float)qscale[q] * S - target );
        if( e < berr ) { berr = e; best = q; }
    }
    return ( (float)qscale[best] * S ) / X264_MAX( target, 1.0f );
}

void x264_mpeg2_cqm_center_decide( x264_t *h, float qpm, int *pi_qp )
{
    int matrices = CHROMA_FORMAT == CHROMA_422 ? 4 : 2;

    if( !h->param.b_cqm_recenter || h->i_mpeg2_cqm_center_count < 2 )
    {
        for( int m = 0; m < matrices; m++ )
        {
            h->quant8_mf_frame[m]   = h->quant8_mf[m];
            h->quant8_bias_frame[m] = h->quant8_bias[m];
            h->quant8_bias0_frame[m] = h->quant8_bias0[m];
            h->dequant8_mf_frame[m] = h->dequant8_mf[m];
        }
        h->i_mpeg2_cqm_center_idx = MPEG2_CQM_CENTER_IDENTITY;
        return;
    }

    float S, target; int best_k, grid_qp;
    int best_qp = mpeg2_cqm_center_select( h, qpm, h->i_mpeg2_cqm_center_idx_emitted, &S, &best_k, &grid_qp, &target );

    for( int m = 0; m < matrices; m++ )
    {
        h->quant8_mf_frame[m]   = h->mpeg2_cqm_center_quant8_mf[best_k][m];
        h->quant8_bias_frame[m] = h->mpeg2_cqm_center_quant8_bias[best_k][m];
        h->quant8_bias0_frame[m] = h->mpeg2_cqm_center_quant8_bias0[best_k][m];
        h->dequant8_mf_frame[m] = h->mpeg2_cqm_center_dequant8_mf[best_k][m];
    }
    h->i_mpeg2_cqm_center_idx = best_k;
    *pi_qp = best_qp;
}

int x264_cqm_init_mpeg2( x264_t *h )
{
    const uint8_t *qscale = x264_qscale_mpeg2[h->param.b_nonlinear_quant];
    int j;
    int matrices = CHROMA_FORMAT == CHROMA_422 ? 4 : 2;
    int deadzone[4] = { 32 - h->param.analyse.i_luma_deadzone[1],   // intra luma
                        32 - h->param.analyse.i_luma_deadzone[0],   // inter luma
                        32 - 21,                                    // intra chroma
                        32 - h->param.analyse.i_luma_deadzone[0] }; // inter chroma
    int intra_mf = j = 1 << ( 10 + h->param.i_intra_dc_precision );
    int intra_bias = X264_MIN( DIV(deadzone[0]<<10, j), (1<<15)/j );

    for( int i = 0; i < matrices; i++ )
    {
        CHECKED_MALLOC( h->quant8_bias[i], (QP_MAX_SPEC_MPEG2+1)*64*sizeof(udctcoef) );
        CHECKED_MALLOC( h->quant8_bias0[i], (QP_MAX_SPEC_MPEG2+1)*64*sizeof(udctcoef) );
        CHECKED_MALLOC( h->  quant8_mf[i], (QP_MAX_SPEC_MPEG2+1)*64*sizeof(udctcoef) );
        CHECKED_MALLOC( h->dequant8_mf[i], (QP_MAX_SPEC_MPEG2+1)*64*sizeof(int) );
    }
    for( int q = 1; q < QP_MAX_SPEC_MPEG2+1; q++ )
    {
        for( int m = 0; m < matrices; m++ )
        {
            for( int i = 0; i < 64; i++ )
            {
                h->  quant8_mf[m][q][i] = j = ( 1 << 17 ) / ( qscale[q] * h->sps->scaling_list[m][i] );
                h->dequant8_mf[m][q][i] = 2 * qscale[q] * h->sps->scaling_list[m][i];
                h->quant8_bias[m][q][i] = X264_MIN( DIV(deadzone[m]<<10, j), (1<<15)/j );
                h->quant8_bias0[m][q][i] = DIV(1<<15, j); // round-to-nearest bias for trellis
            }
            if( !( m & 1 ) ) // intra dc
            {
                h->  quant8_mf[m][q][0] = intra_mf;
                h->quant8_bias[m][q][0] = intra_bias;
                h->quant8_bias0[m][q][0] = (1<<15)/intra_mf;
            }
        }
    }
    if( h->param.b_cqm_recenter )
    {
        h->i_mpeg2_cqm_center_count = MPEG2_CQM_CENTER_COUNT;
        for( int k = 0; k < MPEG2_CQM_CENTER_COUNT; k++ )
        {
            float S = x264_mpeg2_cqm_center_scale[k];
            for( int m = 0; m < matrices; m++ )
            {
                /* Build the scaled base list */
                uint8_t scaled[64];
                for( int i = 0; i < 64; i++ )
                {
                    int v = (int)(h->sps->scaling_list[m][i] * S + 0.5f);
                    scaled[i] = x264_clip3( v, 1, 255 );
                }
                if( !( m & 1 ) ) /* intra DC: centering has no matrix lever */
                    scaled[0] = h->sps->scaling_list[m][0];
                memcpy( h->mpeg2_cqm_center_list[k][m], scaled, 64 );

                CHECKED_MALLOC( h->mpeg2_cqm_center_quant8_mf[k][m],
                                (QP_MAX_SPEC_MPEG2+1)*64*sizeof(udctcoef) );
                CHECKED_MALLOC( h->mpeg2_cqm_center_quant8_bias[k][m],
                                (QP_MAX_SPEC_MPEG2+1)*64*sizeof(udctcoef) );
                CHECKED_MALLOC( h->mpeg2_cqm_center_quant8_bias0[k][m],
                                (QP_MAX_SPEC_MPEG2+1)*64*sizeof(udctcoef) );
                CHECKED_MALLOC( h->mpeg2_cqm_center_dequant8_mf[k][m],
                                (QP_MAX_SPEC_MPEG2+1)*64*sizeof(int) );

                for( int q = 1; q < QP_MAX_SPEC_MPEG2+1; q++ )
                {
                    for( int i = 0; i < 64; i++ )
                    {
                        j = ( 1 << 17 ) / ( qscale[q] * scaled[i] );
                        j = X264_MIN( j, 65535 ); /* quant8_mf is udctcoef (uint16); a deep
                          * scale-down on a small-entry CQM would overflow without this */
                        h->mpeg2_cqm_center_quant8_mf[k][m][q][i] = j;
                        h->mpeg2_cqm_center_dequant8_mf[k][m][q][i] =
                            2 * qscale[q] * scaled[i];
                        h->mpeg2_cqm_center_quant8_bias[k][m][q][i] =
                            X264_MIN( DIV(deadzone[m]<<10, j), (1<<15)/j );
                        h->mpeg2_cqm_center_quant8_bias0[k][m][q][i] = DIV(1<<15, j);
                    }
                    if( !( m & 1 ) ) /* intra dc */
                    {
                        h->mpeg2_cqm_center_quant8_mf[k][m][q][0] = intra_mf;
                        h->mpeg2_cqm_center_quant8_bias[k][m][q][0] = intra_bias;
                        h->mpeg2_cqm_center_quant8_bias0[k][m][q][0] = (1<<15)/intra_mf;
                    }
                }
            }
        }
    }
    else
        h->i_mpeg2_cqm_center_count = 0;

    /* Set per-frame shadow pointers to the base tables */
    for( int m = 0; m < matrices; m++ )
    {
        h->quant8_mf_frame[m]   = h->quant8_mf[m];
        h->quant8_bias_frame[m] = h->quant8_bias[m];
        h->quant8_bias0_frame[m] = h->quant8_bias0[m];
        h->dequant8_mf_frame[m] = h->dequant8_mf[m];
    }
    h->i_mpeg2_cqm_center_idx = MPEG2_CQM_CENTER_IDENTITY; /* S=1.0 identity */
    h->i_mpeg2_cqm_center_idx_emitted = MPEG2_CQM_CENTER_IDENTITY; /* decoder starts at base = identity */

    /* Emergency mode denoising for MPEG-2: ramp the bias up to the internal max QP. */
    x264_emms();
    CHECKED_MALLOC( h->nr_offset_emergency, sizeof(*h->nr_offset_emergency)*(QP_MAX_MPEG2-QP_MAX_SPEC_MPEG2) );
    for( int q = 0; q < QP_MAX_MPEG2 - QP_MAX_SPEC_MPEG2; q++ )
        for( int cat = 0; cat < 2; cat++ ) /* cat 0 = luma, cat 1 = chroma; both 8x8 */
        {
            udctcoef *nr_offset = h->nr_offset_emergency[q][cat];
            double pos = (double)(q+1) / (QP_MAX_MPEG2 - QP_MAX_SPEC_MPEG2);

            for( int i = 0; i < 64; i++ )
            {
                int max = (1 << 15) - 1;
                /* Intra DC is dequantized solely by intra_dc_precision, not qscale. */
                if( i == 0 )
                {
                    nr_offset[i] = 0;
                    continue;
                }
                /* Subtracted from |DCT coeff| pre-quant; a bias of one quant step
                 * (dequant8_mf/2) zeroes a coefficient. Ramp 0 -> 8 steps. */
                double start = h->dequant8_mf[CQM_8PY][QP_MAX_SPEC_MPEG2][i] / 2.0;
                double bias = (pow( 2, pos*(QP_MAX_MPEG2-QP_MAX_SPEC_MPEG2)/4.5 )-1) / (pow( 2, (QP_MAX_MPEG2-QP_MAX_SPEC_MPEG2)/4.5 )-1) * 8 * start;
                nr_offset[i] = X264_MIN( bias + 0.5, max );
            }
        }

    return 0;
fail:
    x264_cqm_delete( h );
    return -1;
}
#endif /* HAVE_MPEG2 && !HIGH_BIT_DEPTH */

#define CQM_DELETE( n, max )\
    for( int i = 0; i < (max); i++ )\
    {\
        int j;\
        for( j = 0; j < i; j++ )\
            if( h->quant##n##_mf[i] == h->quant##n##_mf[j] )\
                break;\
        if( j == i )\
        {\
            x264_free( h->  quant##n##_mf[i] );\
            x264_free( h->dequant##n##_mf[i] );\
            x264_free( h->unquant##n##_mf[i] );\
        }\
        for( j = 0; j < i; j++ )\
            if( h->quant##n##_bias[i] == h->quant##n##_bias[j] )\
                break;\
        if( j == i )\
        {\
            x264_free( h->quant##n##_bias[i] );\
            x264_free( h->quant##n##_bias0[i] );\
        }\
    }

void x264_cqm_delete( x264_t *h )
{
    if( !MPEG2 )
        CQM_DELETE( 4, 4 );
    CQM_DELETE( 8, CHROMA444 || ( MPEG2 && CHROMA_FORMAT == CHROMA_422 ) ? 4 : 2 );
    x264_free( h->nr_offset_emergency );
#if HAVE_MPEG2 && !HIGH_BIT_DEPTH
    if( MPEG2 && h->i_mpeg2_cqm_center_count )
    {
        int matrices = CHROMA_FORMAT == CHROMA_422 ? 4 : 2;
        for( int k = 0; k < h->i_mpeg2_cqm_center_count; k++ )
            for( int m = 0; m < matrices; m++ )
            {
                x264_free( h->mpeg2_cqm_center_quant8_mf[k][m] );
                x264_free( h->mpeg2_cqm_center_dequant8_mf[k][m] );
                x264_free( h->mpeg2_cqm_center_quant8_bias[k][m] );
                x264_free( h->mpeg2_cqm_center_quant8_bias0[k][m] );
            }
    }
#endif
}

static int cqm_parse_jmlist( x264_t *h, const char *buf, const char *name,
                             uint8_t *cqm, const uint8_t *jvt, int length )
{
    int i;

    char *p = strstr( buf, name );
    if( !p )
    {
        memset( cqm, 16, length );
        return 0;
    }

    p += strlen( name );
    if( *p == 'U' || *p == 'V' )
        p++;

    char *nextvar = strstr( p, "INT" );

    for( i = 0; i < length && (p = strpbrk( p, " \t\n," )) && (p = strpbrk( p, "0123456789" )); i++ )
    {
        int coef = -1;
        sscanf( p, "%d", &coef );
        if( i == 0 && coef == 0 )
        {
            memcpy( cqm, jvt, length );
            return 0;
        }
        if( coef < (MPEG2 ? 4 : 1) || coef > 255 )
        {
            x264_log( h, X264_LOG_ERROR, "bad coefficient in list '%s'\n", name );
            return -1;
        }
        cqm[i] = coef;
    }

    if( (nextvar && p > nextvar) || i != length )
    {
        x264_log( h, X264_LOG_ERROR, "not enough coefficients in list '%s'\n", name );
        return -1;
    }

    return 0;
}

int x264_cqm_parse_file( x264_t *h, const char *filename )
{
    char *p;
    int b_error = 0;

    h->param.i_cqm_preset = X264_CQM_CUSTOM;

    char *buf = x264_slurp_file( filename );
    if( !buf )
    {
        x264_log( h, X264_LOG_ERROR, "can't open file '%s'\n", filename );
        return -1;
    }

    while( (p = strchr( buf, '#' )) != NULL )
        memset( p, ' ', strcspn( p, "\n" ) );

#if HAVE_MPEG2
    if( MPEG2 )
    {
        // x264_cqm_intra_mpeg2 is transposed, but param.cqm_8i* is not
        uint8_t intra[64];
        for( int i = 0; i < 8; i++ )
            for( int j = 0; j < 8; j++ )
                intra[8*i+j] = x264_cqm_intra_mpeg2[8*j+i];
        b_error |= cqm_parse_jmlist( h, buf, "INTRA_LUMA", h->param.cqm_8iy, intra, 64 );
        b_error |= cqm_parse_jmlist( h, buf, "INTER_LUMA", h->param.cqm_8py, x264_cqm_flat16, 64 );
        int csp = h->param.i_csp & X264_CSP_MASK;
        if( csp >= X264_CSP_I422 && csp < X264_CSP_I444 )
        {
            b_error |= cqm_parse_jmlist( h, buf, "INTRA_CHROMA", h->param.cqm_8ic, h->param.cqm_8iy, 64 );
            b_error |= cqm_parse_jmlist( h, buf, "INTER_CHROMA", h->param.cqm_8pc, h->param.cqm_8py, 64 );
        }
    }
    else
#endif
    {
        b_error |= cqm_parse_jmlist( h, buf, "INTRA4X4_LUMA",   h->param.cqm_4iy, x264_cqm_jvt4i, 16 );
        b_error |= cqm_parse_jmlist( h, buf, "INTER4X4_LUMA",   h->param.cqm_4py, x264_cqm_jvt4p, 16 );
        b_error |= cqm_parse_jmlist( h, buf, "INTRA4X4_CHROMA", h->param.cqm_4ic, x264_cqm_jvt4i, 16 );
        b_error |= cqm_parse_jmlist( h, buf, "INTER4X4_CHROMA", h->param.cqm_4pc, x264_cqm_jvt4p, 16 );
        b_error |= cqm_parse_jmlist( h, buf, "INTRA8X8_LUMA",   h->param.cqm_8iy, x264_cqm_jvt8i, 64 );
        b_error |= cqm_parse_jmlist( h, buf, "INTER8X8_LUMA",   h->param.cqm_8py, x264_cqm_jvt8p, 64 );
        if( CHROMA444 )
        {
            b_error |= cqm_parse_jmlist( h, buf, "INTRA8X8_CHROMA", h->param.cqm_8ic, x264_cqm_jvt8i, 64 );
            b_error |= cqm_parse_jmlist( h, buf, "INTER8X8_CHROMA", h->param.cqm_8pc, x264_cqm_jvt8p, 64 );
        }
    }

    x264_free( buf );
    return b_error;
}

