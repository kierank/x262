#include <stdio.h>
#include <string.h>
#include <math.h>
#include "common/common.h"
#include "common/cpu.h"

struct x264_speedcontrol_t
{
    // all times are in usec
    int64_t timestamp;   // when was speedcontrol last invoked
    int64_t cpu_time;    // time spent encoding the previous frame
    int64_t buffer_size; // assumed application-side buffer of frames to be streamed,
    int64_t buffer_fill; //   where full = we don't have to hurry
    int64_t compensation_period; // how quickly we try to return to the target buffer fullness
    float fps, spf;
    int preset;          // which setting was used in the previous frame
    int prev_frame;
    float cplx_num;      // rolling average of estimated spf for preset #0
    float cplx_den;
    float cplx_decay;
    float dither;

    int first;
    int buffer_complete;

    struct
    {
        int64_t min_buffer, max_buffer;
        double avg_preset;
        int den;
    } stat;
};

void x264_speedcontrol_new( x264_t *h )
{
    x264_speedcontrol_t *sc = h->sc = x264_malloc( sizeof(x264_speedcontrol_t) );
    x264_emms();
    memset( sc, 0, sizeof(x264_speedcontrol_t) );

    if( h->param.sc.f_speed <= 0 )
        h->param.sc.f_speed = 1;
    sc->fps = h->param.i_fps_num / h->param.i_fps_den;
    sc->spf = 1e6 / sc->fps;
    h->param.sc.i_buffer_size = X264_MAX( 3, h->param.sc.i_buffer_size );
    sc->buffer_size = h->param.sc.i_buffer_size * 1e6 / sc->fps;
    sc->buffer_fill = sc->buffer_size * h->param.sc.f_buffer_init;
    sc->buffer_fill = x264_clip3( sc->buffer_fill, sc->spf, sc->buffer_size );
    sc->compensation_period = sc->buffer_size/4;
    sc->timestamp = x264_mdate();
    sc->preset = -1;
    sc->prev_frame = 0;
    sc->cplx_num = 3e3; //FIXME estimate initial complexity
    sc->cplx_den = .1;
    sc->cplx_decay = 1 - 1./h->param.sc.i_buffer_size;
    sc->stat.min_buffer = sc->buffer_size;
    sc->stat.max_buffer = 0;
    sc->first = 1;
    sc->buffer_complete = 0;
}

void x264_speedcontrol_delete( x264_t *h )
{
    x264_speedcontrol_t *sc = h->sc;
    if( !sc )
        return;
    x264_log( h, X264_LOG_INFO, "speedcontrol: avg preset=%.3f  buffer min=%.3f max=%.3f\n",
              sc->stat.avg_preset / sc->stat.den,
              (float)sc->stat.min_buffer / sc->buffer_size,
              (float)sc->stat.max_buffer / sc->buffer_size );
//  x264_log( h, X264_LOG_INFO, "speedcontrol: avg cplx=%.5f\n", sc->cplx_num / sc->cplx_den );
    x264_free( sc );
}

static int dither( x264_speedcontrol_t *sc, float f )
{
    int i = f;
    if( f < 0 )
        i--;
    sc->dither += f - i;
    if( sc->dither >= 1. )
    {
        sc->dither--;
        i++;
    }
    return i;
}

typedef struct
{
    float time; // relative encoding time, compared to the other presets
    int subme;
    int me;
    int refs;
    int mix;
    int trellis;
    int partitions;
    int chromame;
    float psy_rd;
    float psy_trellis;
} sc_preset_t;

static const sc_preset_t presets[SC_PRESETS] =
{
#define I4 X264_ANALYSE_I4x4
#define I8 X264_ANALYSE_I8x8
#define P8 X264_ANALYSE_PSUB16x16
#define B8 X264_ANALYSE_BSUB16x16
/*0*/    { .time=1.000, .subme=1, .me=X264_ME_DIA, .refs=1, .mix=0, .chromame=0, .trellis=0, .partitions=0, .psy_rd=0 },
/*1*/    { .time=1.009, .subme=1, .me=X264_ME_DIA, .refs=1, .mix=0, .chromame=0, .trellis=0, .partitions=I8|I4, .psy_rd=0 },
/*2*/    { .time=1.843, .subme=3, .me=X264_ME_HEX, .refs=1, .mix=0, .chromame=0, .trellis=0, .partitions=I8|I4, .psy_rd=0 },
/*3*/    { .time=1.984, .subme=5, .me=X264_ME_HEX, .refs=1, .mix=0, .chromame=0, .trellis=0, .partitions=I8|I4, .psy_rd=1.0 },
/*4*/    { .time=2.289, .subme=6, .me=X264_ME_HEX, .refs=1, .mix=0, .chromame=0, .trellis=0, .partitions=I8|I4, .psy_rd=1.0 },
/*5*/    { .time=3.113, .subme=6, .me=X264_ME_HEX, .refs=1, .mix=0, .chromame=0, .trellis=1, .partitions=I8|I4, .psy_rd=1.0 },
/*6*/    { .time=3.400, .subme=6, .me=X264_ME_HEX, .refs=2, .mix=0, .chromame=0, .trellis=1, .partitions=I8|I4, .psy_rd=1.0 },
/*7*/    { .time=3.755, .subme=7, .me=X264_ME_HEX, .refs=2, .mix=0, .chromame=0, .trellis=1, .partitions=I8|I4, .psy_rd=1.0 },
/*8*/    { .time=4.592, .subme=7, .me=X264_ME_HEX, .refs=2, .mix=0, .chromame=0, .trellis=1, .partitions=I8|I4|P8|B8, .psy_rd=1.0 },
/*9*/    { .time=4.730, .subme=7, .me=X264_ME_HEX, .refs=3, .mix=0, .chromame=0, .trellis=1, .partitions=I8|I4|P8|B8, .psy_rd=1.0 },
/*10*/   { .time=5.453, .subme=8, .me=X264_ME_HEX, .refs=3, .mix=0, .chromame=0, .trellis=1, .partitions=I8|I4|P8|B8, .psy_rd=1.0 },
/*11*/   { .time=8.277, .subme=8, .me=X264_ME_UMH, .refs=3, .mix=1, .chromame=1, .trellis=1, .partitions=I8|I4|P8|B8, .psy_rd=1.0 },
/*12*/   { .time=8.410, .subme=8, .me=X264_ME_UMH, .refs=4, .mix=1, .chromame=1, .trellis=1, .partitions=I8|I4|P8|B8, .psy_rd=1.0 }
};

static void apply_preset( x264_t *h, int preset )
{
    x264_speedcontrol_t *sc = h->sc;
    preset = x264_clip3( preset, 0, h->param.sc.max_preset-1 );
    //if( preset != sc->preset )
    {
        const sc_preset_t *s = &presets[preset];
        x264_param_t p = h->param;

        p.i_frame_reference = s->refs;
        p.analyse.inter = s->partitions;
        p.analyse.i_subpel_refine = s->subme;
        p.analyse.i_me_method = s->me;
        p.analyse.i_trellis = s->trellis;
        p.analyse.b_mixed_references = s->mix;
        p.analyse.b_chroma_me = s->chromame;
        p.analyse.f_psy_rd = s->psy_rd;
        p.analyse.f_psy_trellis = s->psy_trellis;
        x264_encoder_reconfig( h, &p );
        sc->preset = preset;
        x264_log( h, X264_LOG_DEBUG, "Applying speedcontrol preset %d.\n", preset );
    }
}

void x264_speedcontrol_frame_end( x264_t *h )
{
    x264_speedcontrol_t *sc = h->sc;
    if( h->param.sc.b_alt_timer )
        sc->cpu_time = x264_mdate() - sc->timestamp;
}

void x264_speedcontrol_frame( x264_t *h )
{
    x264_speedcontrol_t *sc = h->sc;
    int64_t t, delta_t, delta_buffer;
    int delta_f;

    x264_emms();

    // update buffer state after encoding and outputting the previous frame(s)
    if( sc->first )
    {
        t = sc->timestamp = x264_mdate();
        sc->first = 0;
    }
    else
        t = x264_mdate();

    delta_f = h->i_frame - sc->prev_frame;
    delta_t = t - sc->timestamp;
    delta_buffer = delta_f * sc->spf / h->param.sc.f_speed - delta_t;
    if( !sc->buffer_complete )
        sc->buffer_fill += delta_buffer;
    sc->prev_frame = h->i_frame;
    sc->timestamp = t;

    // update the time predictor
    if( delta_f )
    {
        int cpu_time = h->param.sc.b_alt_timer ? sc->cpu_time : delta_t;
        float decay = powf( sc->cplx_decay, delta_f );
        sc->cplx_num *= decay;
        sc->cplx_den *= decay;
        sc->cplx_num += cpu_time / presets[sc->preset].time;
        sc->cplx_den += delta_f;

        sc->stat.avg_preset += sc->preset * delta_f;
        sc->stat.den += delta_f;
    }
    sc->stat.min_buffer = X264_MIN( sc->buffer_fill, sc->stat.min_buffer );
    sc->stat.max_buffer = X264_MAX( sc->buffer_fill, sc->stat.max_buffer );

    if( sc->buffer_fill > sc->buffer_size ) // oops, cpu was idle
    {
        // not really an error, but we'll warn for debugging purposes
        static int64_t idle_t = 0, print_interval = 0;
        idle_t += sc->buffer_fill - sc->buffer_size;
        if( t - print_interval > 1e6 )
        {
            x264_log( h, X264_LOG_DEBUG, "speedcontrol idle (%.6f sec)\n", idle_t/1e6 );
            print_interval = t;
            idle_t = 0;
        }
        sc->buffer_fill = sc->buffer_size;
    }
    else if( sc->buffer_fill < 0 && delta_buffer < 0 ) // oops, we're late
    {
        // don't clip fullness to 0; we'll hope the real buffer was bigger than
        // specified, and maybe we can catch up. if the application had to drop
        // frames, then it should override the buffer fullness (FIXME implement this).
        x264_log( h, X264_LOG_WARNING, "speedcontrol underflow (%.6f sec)\n", sc->buffer_fill/1e6 );
    }

    {
        // pick the preset that should return the buffer to 3/4-full within a time
        // specified by compensation_period
        float target = sc->spf / h->param.sc.f_speed
                     * (sc->buffer_fill + sc->compensation_period)
                     / (sc->buffer_size*3/4 + sc->compensation_period);
        float cplx = sc->cplx_num / sc->cplx_den;
        float set, t0, t1;
	float filled = (float) sc->buffer_fill / sc->buffer_size;
        int i;
        t0 = presets[0].time * cplx;
        for( i=1;; i++ )
        {
            t1 = presets[i].time * cplx;
            if( t1 >= target || i == h->param.sc.max_preset-1 )
                break;
            t0 = t1;
        }
        // linear interpolation between states
        set = i-1 + (target - t0) / (t1 - t0);
        // Even if our time estimations in the SC_PRESETS array are off
        // this will push us towards our target fullness
        set += (20 * (filled-0.75));
        set = x264_clip3f( set, 0 , h->param.sc.max_preset-1 );
        apply_preset( h, dither( sc, set ) );

        // FIXME
        if (h->param.i_log_level >= X264_LOG_DEBUG)
        {
            static float cpu, wall, tgt, den;
            float decay = 1-1/100.;
            cpu = cpu*decay + sc->cpu_time;
            wall = wall*decay + delta_t;
            tgt = tgt*decay + target;
            den = den*decay + 1;
            x264_log( h, X264_LOG_DEBUG, "speed: %.2f %d[%.5f] (t/c/w: %6.0f/%6.0f/%6.0f = %.4f) fps=%.2f\r",
                     set, sc->preset, (float)sc->buffer_fill / sc->buffer_size,
                     tgt/den, cpu/den, wall/den, cpu/wall, 1e6*den/wall );
        }
    }

}

void x264_speedcontrol_sync( x264_t *h, float f_buffer_fill, int i_buffer_size, int buffer_complete )
{
    x264_speedcontrol_t *sc = h->sc;
    if( !h->param.sc.i_buffer_size )
        return;
    if( i_buffer_size )
        h->param.sc.i_buffer_size = X264_MAX( 3, h->param.sc.i_buffer_size );
    sc->buffer_size = h->param.sc.i_buffer_size * 1e6 / sc->fps;
    sc->buffer_fill = sc->buffer_size * f_buffer_fill;
    sc->buffer_complete = !!buffer_complete;
}
