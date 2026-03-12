#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/times.h>
#include <unistd.h>

#include <system.h>

/*
 * Task 7 Step-2 software driver
 *
 * This program evaluates:
 *   f(x) = 0.5*x + x^3*cos((x-128)/128)
 * and then sums f(x) over vector cases C1/C2/C3.
 *
 * The arithmetic datapath is intentionally mapped to split custom instructions
 * (ADD/SUB/MUL/COS) so we can profile accelerator usage and software overhead.
 */

#define TASK7_MODE 3

/* Number of repeated runs per case to smooth timing noise. */
#define NUM_RUNS 10
/* Upper bound that safely holds the largest coursework vector (C3). */
#define MAX_VECTOR_LEN 70000

#define CASE4_LEN 2323
#define CASE4_SEED 334u
#define CASE4_MAXVAL 255.0f

#if TASK7_MODE == 2

#define CI_STEP2_MUL(a, b) ALT_CI_CUSTOM_FP_MUL_0((a), (b))
#define CI_STEP2_ADD(a, b) ALT_CI_CUSTOM_FP_ADD_0((a), (b))
#define CI_STEP2_SUB(a, b) ALT_CI_CUSTOM_FP_SUB_0((a), (b))
#define CI_STEP2_COS(a, b) ALT_CI_CUSTOM_COS((a), (b))

#elif TASK7_MODE == 3

#define CI_STEP3_FX(a) ALT_CI_CUSTOM_SINGLE_F_ACCELERATOR_0((a), 0u)

#endif

typedef struct {
    unsigned long mul_ticks;
    unsigned long add_ticks;
    unsigned long sub_ticks;
    unsigned long cos_ticks;
    unsigned long mul_calls;
    unsigned long add_calls;
    unsigned long sub_calls;
    unsigned long cos_calls;
} profile_t;

typedef struct {
    const char *tag;
    int len;
    float step;
} case_cfg_t;

static inline uint32_t f32_to_u32(float x) {
    union {
        float f;
        uint32_t u;
    } v;
    v.f = x;
    return v.u;
}

static inline float u32_to_f32(uint32_t x) {
    union {
        float f;
        uint32_t u;
    } v;
    v.u = x;
    return v.f;
}

static inline unsigned long now_ticks(void) {
    return (unsigned long)times(NULL);
}

static void generate_vector(float x[], int len, float step) {
    int i;

    x[0] = 0.0f;
    for (i = 1; i < len; i++) {
        x[i] = x[i - 1] + step;
    }
}

static void generate_random_vector(float x[], int len) {
    int i;
    srand(CASE4_SEED);

    for (i = 0; i < len; i++) {
        x[i] = ((float)rand() / (float)RAND_MAX) * CASE4_MAXVAL;
    }
}

#if TASK7_MODE == 2

static uint32_t ci_mul(uint32_t a, uint32_t b, profile_t *p) {
    unsigned long t0 = now_ticks();
    uint32_t r = CI_STEP2_MUL(a, b);
    unsigned long t1 = now_ticks();

    p->mul_ticks += (t1 - t0);
    p->mul_calls++;

    return r;
}

static uint32_t ci_add(uint32_t a, uint32_t b, profile_t *p) {
    unsigned long t0 = now_ticks();
    uint32_t r = CI_STEP2_ADD(a, b);
    unsigned long t1 = now_ticks();

    p->add_ticks += (t1 - t0);
    p->add_calls++;

    return r;
}

static uint32_t ci_sub(uint32_t a, uint32_t b, profile_t *p) {
    unsigned long t0 = now_ticks();
    uint32_t r = CI_STEP2_SUB(a, b);
    unsigned long t1 = now_ticks();

    p->sub_ticks += (t1 - t0);
    p->sub_calls++;

    return r;
}

static uint32_t ci_cos(uint32_t a, profile_t *p) {
    unsigned long t0 = now_ticks();
    uint32_t r = CI_STEP2_COS(a, 0u);
    unsigned long t1 = now_ticks();

    p->cos_ticks += (t1 - t0);
    p->cos_calls++;

    return r;
}

#endif

#if TASK7_MODE == 2

static float eval_fx(float x, profile_t *p) {

    uint32_t xb = f32_to_u32(x);
    uint32_t c_half = f32_to_u32(0.5f);
    uint32_t c_128 = f32_to_u32(128.0f);
    uint32_t c_inv128 = f32_to_u32(1.0f / 128.0f);

    uint32_t x_minus_128 = ci_sub(xb, c_128, p);
    uint32_t angle = ci_mul(x_minus_128, c_inv128, p);

    uint32_t half_x = ci_mul(xb, c_half, p);
    uint32_t x2 = ci_mul(xb, xb, p);
    uint32_t x3 = ci_mul(x2, xb, p);

    uint32_t c = ci_cos(angle, p);
    uint32_t term = ci_mul(x3, c, p);

    uint32_t fx = ci_add(half_x, term, p);

    return u32_to_f32(fx);
}

#else

static float eval_fx(float x, profile_t *p) {

    uint32_t xb = f32_to_u32(x);
    uint32_t r = CI_STEP3_FX(xb);

    return u32_to_f32(r);
}

#endif

static float compute_fx(const float x[], int len, profile_t *p) {

    float sum = 0.0f;

    for (int i = 0; i < len; i++) {
        sum += eval_fx(x[i], p);
    }

    return sum;
}

static double compute_fx_ref_double(const float x[], int len) {

    double sum = 0.0;

    for (int i = 0; i < len; i++) {

        double xd = (double)x[i];
        double angle = (xd - 128.0) / 128.0;

        sum += 0.5 * xd + xd * xd * xd * cos(angle);
    }

    return sum;
}

static void print_profile_line(const char *name,
                               unsigned long ticks,
                               unsigned long calls) {

    double per_call =
        (calls == 0ul) ? 0.0 : ((double)ticks / (double)calls);

    printf("%s=%lu ticks (%lu calls, %.9f ticks/call)\n",
           name,
           ticks,
           calls,
           per_call);
}

static void run_case(const case_cfg_t *cfg, float xbuf[]) {

    profile_t profile = {0};

    float hw_out = 0.0f;

    double ref_out;
    double abs_err;
    double rel_err;

    unsigned long t0;
    unsigned long t1;
    unsigned long total_ticks;

    if (cfg->step >= 0.0f)
        generate_vector(xbuf, cfg->len, cfg->step);
    else
        generate_random_vector(xbuf, cfg->len);

    ref_out = compute_fx_ref_double(xbuf, cfg->len);

    t0 = now_ticks();

    for (int k = 0; k < NUM_RUNS; k++) {
        hw_out = compute_fx(xbuf, cfg->len, &profile);
    }

    t1 = now_ticks();

    total_ticks = t1 - t0;

    abs_err = fabs((double)hw_out - ref_out);
    rel_err = (ref_out == 0.0) ? 0.0 : (abs_err / fabs(ref_out));

#if TASK7_MODE == 2

    unsigned long accel_ticks =
        profile.mul_ticks +
        profile.add_ticks +
        profile.sub_ticks +
        profile.cos_ticks;

    long long overhead_ticks =
        (long long)total_ticks -
        (long long)accel_ticks;

    printf("\n[Step-2][%s] len=%d step=%.9g runs=%d\n",
           cfg->tag,
           cfg->len,
           (double)cfg->step,
           NUM_RUNS);

    printf("[Step-2][%s] F_hw=%.10e F_ref=%.10e abs_err=%.3e rel_err=%.3e\n",
           cfg->tag,
           (double)hw_out,
           ref_out,
           abs_err,
           rel_err);

    printf("[Step-2][%s] total=%lu ticks avg=%lu ticks/run\n",
           cfg->tag,
           total_ticks,
           (unsigned long)(total_ticks / NUM_RUNS));

    printf("[Step-2][%s] accel_sum=%lu ticks overhead=%lld ticks\n",
           cfg->tag,
           accel_ticks,
           overhead_ticks);

    printf("[Step-2][%s] ", cfg->tag);
    print_profile_line("mul", profile.mul_ticks, profile.mul_calls);

    printf("[Step-2][%s] ", cfg->tag);
    print_profile_line("add", profile.add_ticks, profile.add_calls);

    printf("[Step-2][%s] ", cfg->tag);
    print_profile_line("sub", profile.sub_ticks, profile.sub_calls);

    printf("[Step-2][%s] ", cfg->tag);
    print_profile_line("cos", profile.cos_ticks, profile.cos_calls);

#else

    printf("\n[Step-3][%s] len=%d step=%.9g runs=%d\n",
           cfg->tag,
           cfg->len,
           (double)cfg->step,
           NUM_RUNS);

    printf("[Step-3][%s] F_hw=%.10e F_ref=%.10e abs_err=%.3e rel_err=%.3e\n",
           cfg->tag,
           (double)hw_out,
           ref_out,
           abs_err,
           rel_err);

    printf("[Step-3][%s] total=%lu ticks avg=%lu ticks/run\n",
           cfg->tag,
           total_ticks,
           (unsigned long)(total_ticks / NUM_RUNS));

#endif
}

int main(void) {

    static float xbuf[MAX_VECTOR_LEN];

    const case_cfg_t cases[] = {
        {"C1", 52, 5.0f},
        {"C2", 2041, 1.0f / 8.0f},
        {"C3", 65281, 1.0f / 256.0f},
        {"C4", CASE4_LEN, -1.0f},
    };

    const int case_count =
        (int)(sizeof(cases) / sizeof(cases[0]));

    printf("Task7 software run started. tick_hz=%d\n",
           ALT_SYS_CLK_TICKS_PER_SEC);

#if TASK7_MODE == 2

    printf("CI opcodes: add=%d sub=%d mul=%d cos=%d\n",
           ALT_CI_CUSTOM_FP_ADD_0_N,
           ALT_CI_CUSTOM_FP_SUB_0_N,
           ALT_CI_CUSTOM_FP_MUL_0_N,
           ALT_CI_CUSTOM_COS_N);

#else

    printf("CI opcode: single_fx=%d\n",
           ALT_CI_CUSTOM_SINGLE_F_ACCELERATOR_0_N);

#endif

    for (int i = 0; i < case_count; i++) {
        run_case(&cases[i], xbuf);
    }

    printf("\nTask7 software run finished.\n");

    return 0;
}
