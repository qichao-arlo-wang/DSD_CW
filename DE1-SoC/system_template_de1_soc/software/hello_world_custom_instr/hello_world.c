#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/times.h>
#include <unistd.h>

#include <system.h>

/*
 * Task 7 software driver.
 *
 * Default mode in this file is Step-2 (split CI path) for Task 7b reruns.
 * Output is intentionally kept concise to reduce measurement perturbation.
 */

#ifndef TASK7_MODE
#define TASK7_MODE 5
#endif

/* 0: only coarse total ticks around the whole run (recommended for rerun timing). */
/* 1: also record per-CI call wrapper timing/counters (adds perturbation). */
#define STEP2_PROFILE_INNER 0

/* Number of repeated runs per case to smooth timing noise. */
#define NUM_RUNS 10
/* Upper bound that safely holds the largest coursework vector (C3). */
#define MAX_VECTOR_LEN 70000

#define CASE4_LEN 2323
#define CASE4_SEED 334u
#define CASE4_MAXVAL 255.0f

/* CI binding:
 * mode 2 -> split operators (mul/add/sub/cos),
 * mode 3 -> single fused f(x) operator,
 * mode 4 -> original Task-8 accumulate wrapper,
 * mode 5 -> stateful Task-8 pipelined frame CI (INIT/PUSH/GET_RESULT).
 */
#if TASK7_MODE == 2

#define CI_STEP2_MUL(a, b) ALT_CI_CUSTOM_FP_MUL_0((a), (b))
#define CI_STEP2_ADD(a, b) ALT_CI_CUSTOM_FP_ADD_0((a), (b))
#define CI_STEP2_SUB(a, b) ALT_CI_CUSTOM_FP_SUB_0((a), (b))
#define CI_STEP2_COS(a, b) ALT_CI_CUSTOM_COS((a), (b))

#elif TASK7_MODE == 3

#define CI_STEP3_FX(a) ALT_CI_CUSTOM_SINGLE_F_ACCELERATOR_0((a), 0u)
/* Step-3 reduction uses custom fp add to avoid CPU-side float accumulate cost. */
#define CI_STEP3_ACC_ADD(a, b) ALT_CI_CUSTOM_FP_ADD_0((a), (b))

#if !defined(ALT_CI_CUSTOM_FP_ADD_0_N)
#error "TASK7_MODE=3 requires custom fp add CI (ALT_CI_CUSTOM_FP_ADD_0)."
#endif

#elif TASK7_MODE == 4

#define CI_STEP8_ACCUM(acc, x) ALT_CI_CUSTOM_F_ACCUM_0((acc), (x))

#elif TASK7_MODE == 5

/*
 * Extended custom instruction for the pipelined Task-8 frame reducer.
 *
 * Platform Designer must expose the component instance as CUSTOM_FSUM_PIPE so
 * that system.h defines ALT_CI_CUSTOM_FSUM_PIPE_0_N. If you use a different
 * instance name, update the symbol below to match the generated system.h entry.
 */
#if !defined(ALT_CI_CUSTOM_F_ACCUM_PIPE_0_N)
#error "TASK7_MODE=5 requires ALT_CI_CUSTOM_FSUM_PIPE_0_N from system.h."
#endif

#define CI_STEP8_PIPE_BASE_N ALT_CI_CUSTOM_F_ACCUM_PIPE_0_N
#define CI_STEP8_PIPE_OP_INIT 0u
#define CI_STEP8_PIPE_OP_PUSH_X 1u
#define CI_STEP8_PIPE_OP_GET_RESULT 2u
#define CI_STEP8_PIPE_RAW(op, a, b) \
    ((uint32_t)__builtin_custom_inii((int)(CI_STEP8_PIPE_BASE_N + ((op) & 0xffu)), \
                                     (int)(uint32_t)(a),                                  \
                                     (int)(uint32_t)(b)))

#define CI_STEP8_PIPE_INIT(len) \
    CI_STEP8_PIPE_RAW(CI_STEP8_PIPE_OP_INIT, (len), 0u)
#define CI_STEP8_PIPE_PUSH_X(x_bits) \
    CI_STEP8_PIPE_RAW(CI_STEP8_PIPE_OP_PUSH_X, (x_bits), 0u)
#define CI_STEP8_PIPE_GET_RESULT() \
    CI_STEP8_PIPE_RAW(CI_STEP8_PIPE_OP_GET_RESULT, 0u, 0u)

#endif

/* Optional per-operator profiling counters for Step-2 detailed breakdown. */
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

/* Test-case descriptor:
 * step >= 0  -> arithmetic progression vector,
 * step < 0   -> seeded random vector (C4).
 */
typedef struct {
    const char *tag;
    int len;
    float step;
} case_cfg_t;

/* Preserve IEEE-754 bit pattern when passing float through CI integer ports. */
static inline uint32_t f32_to_u32(float x) {
    union {
        float f;
        uint32_t u;
    } v;
    v.f = x;
    return v.u;
}

/* Restore IEEE-754 float from CI return word. */
static inline float u32_to_f32(uint32_t x) {
    union {
        float f;
        uint32_t u;
    } v;
    v.u = x;
    return v.f;
}

/* System tick helper used for coarse profiling around CI calls/functions. */
static inline unsigned long now_ticks(void) {
    return (unsigned long)times(NULL);
}

/* Build deterministic vector for arithmetic progression cases. */
static void generate_vector(float x[], int len, float step) {
    int i;

    x[0] = 0.0f;
    for (i = 1; i < len; i++) {
        x[i] = x[i - 1] + step;
    }
}

/* Build deterministic random vector for C4 using fixed seed. */
static void generate_random_vector(float x[], int len) {
    int i;
    srand(CASE4_SEED);

    for (i = 0; i < len; i++) {
        x[i] = ((float)rand() / (float)RAND_MAX) * CASE4_MAXVAL;
    }
}

#if TASK7_MODE == 2

/* Step-2 CI wrapper with tick accounting (MUL). */
static uint32_t ci_mul(uint32_t a, uint32_t b, profile_t *p) {
#if STEP2_PROFILE_INNER
    unsigned long t0 = now_ticks();
    uint32_t r = CI_STEP2_MUL(a, b);
    unsigned long t1 = now_ticks();

    p->mul_ticks += (t1 - t0);
    p->mul_calls++;

    return r;
#else
    (void)p;
    return CI_STEP2_MUL(a, b);
#endif
}

/* Step-2 CI wrapper with tick accounting (ADD). */
static uint32_t ci_add(uint32_t a, uint32_t b, profile_t *p) {
#if STEP2_PROFILE_INNER
    unsigned long t0 = now_ticks();
    uint32_t r = CI_STEP2_ADD(a, b);
    unsigned long t1 = now_ticks();

    p->add_ticks += (t1 - t0);
    p->add_calls++;

    return r;
#else
    (void)p;
    return CI_STEP2_ADD(a, b);
#endif
}

/* Step-2 CI wrapper with tick accounting (SUB). */
static uint32_t ci_sub(uint32_t a, uint32_t b, profile_t *p) {
#if STEP2_PROFILE_INNER
    unsigned long t0 = now_ticks();
    uint32_t r = CI_STEP2_SUB(a, b);
    unsigned long t1 = now_ticks();

    p->sub_ticks += (t1 - t0);
    p->sub_calls++;

    return r;
#else
    (void)p;
    return CI_STEP2_SUB(a, b);
#endif
}

/* Step-2 CI wrapper with tick accounting (COS). */
static uint32_t ci_cos(uint32_t a, profile_t *p) {
#if STEP2_PROFILE_INNER
    unsigned long t0 = now_ticks();
    uint32_t r = CI_STEP2_COS(a, 0u);
    unsigned long t1 = now_ticks();

    p->cos_ticks += (t1 - t0);
    p->cos_calls++;

    return r;
#else
    (void)p;
    return CI_STEP2_COS(a, 0u);
#endif
}

#endif

#if TASK7_MODE == 5

/*
 * Task-8 pipelined frame CI helper:
 *   1. INIT(len)
 *   2. PUSH_X(x_i) for each sample
 *   3. GET_RESULT() blocks until frame completion and returns F(X)
 *
 * Status bit assignment matches task8_ci_fsum_pipe.sv:
 *   bit0 busy
 *   bit1 in_ready
 *   bit2 frame_done_latched
 *   bit3 core_error_latched
 *   bit4 protocol_error_latched
 */
static uint32_t step8_pipe_compute(const float x[], int len) {
    CI_STEP8_PIPE_INIT((uint32_t)len);

    for (int i = 0; i < len; i++) {
        CI_STEP8_PIPE_PUSH_X(f32_to_u32(x[i]));
    }

    return CI_STEP8_PIPE_GET_RESULT();
}

#endif

#if TASK7_MODE == 2

/* Split-CI implementation of:
 * f(x) = 0.5*x + x^3*cos((x-128)/128)
 */
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

#elif TASK7_MODE == 3

/* Fused single-CI implementation of f(x) (Step-3). */
static float eval_fx(float x, profile_t *p) {
    (void)p;

    uint32_t xb = f32_to_u32(x);
    uint32_t r = CI_STEP3_FX(xb);

    return u32_to_f32(r);
}

#endif

/* Compute full reduction F(X) = sum_i f(x_i). */
static float compute_fx(const float x[], int len, profile_t *p) {
    (void)p;

    float sum = 0.0f;

#if TASK7_MODE == 4

    uint32_t acc = f32_to_u32(0.0f);

    for (int i = 0; i < len; i++) {

        uint32_t xb = f32_to_u32(x[i]);
        acc = CI_STEP8_ACCUM(acc, xb);

    }

    sum = u32_to_f32(acc);

#elif TASK7_MODE == 5

    sum = u32_to_f32(step8_pipe_compute(x, len));

#elif TASK7_MODE == 3

    /* Keep Step-3 reduction fully on custom FP path (no CPU float add in loop). */
    uint32_t sum_bits = f32_to_u32(0.0f);

    for (int i = 0; i < len; i++) {
        uint32_t fx_bits = f32_to_u32(eval_fx(x[i], p));
        sum_bits = CI_STEP3_ACC_ADD(sum_bits, fx_bits);
    }

    sum = u32_to_f32(sum_bits);

#else

    for (int i = 0; i < len; i++) {
        sum += eval_fx(x[i], p);
    }

#endif

    return sum;
}

/* Double-precision software reference used for correctness/error reporting. */
static double compute_fx_ref_double(const float x[], int len) {

    double sum = 0.0;

    for (int i = 0; i < len; i++) {

        double xd = (double)x[i];
        double angle = (xd - 128.0) / 128.0;

        sum += 0.5 * xd + xd * xd * xd * cos(angle);
    }

    return sum;
}

/* Print helper for one accelerator profile line. */
#if TASK7_MODE == 2 && STEP2_PROFILE_INNER
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
#endif

/* Run one configured case:
 * vector generation -> reference evaluation -> repeated HW runs -> report.
 */
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

#if STEP2_PROFILE_INNER
    /* Sum of measured CI ticks in split-accelerator mode. */
    unsigned long accel_ticks =
        profile.mul_ticks +
        profile.add_ticks +
        profile.sub_ticks +
        profile.cos_ticks;

    /* Residual time not inside measured CI wrappers (software overhead). */
    long long overhead_ticks =
        (long long)total_ticks -
        (long long)accel_ticks;
#endif

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

#if STEP2_PROFILE_INNER
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
#endif

#elif TASK7_MODE == 3

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

#elif TASK7_MODE == 4

    printf("\n[Step-4][%s] len=%d step=%.9g runs=%d\n",
           cfg->tag,
           cfg->len,
           (double)cfg->step,
           NUM_RUNS);

    printf("[Step-4][%s] F_hw=%.10e F_ref=%.10e abs_err=%.3e rel_err=%.3e\n",
           cfg->tag,
           (double)hw_out,
           ref_out,
           abs_err,
           rel_err);

    printf("[Step-4][%s] total=%lu ticks avg=%lu ticks/run\n",
           cfg->tag,
           total_ticks,
           (unsigned long)(total_ticks / NUM_RUNS));

#elif TASK7_MODE == 5

    printf("\n[Step-4-pipe][%s] len=%d step=%.9g runs=%d\n",
           cfg->tag,
           cfg->len,
           (double)cfg->step,
           NUM_RUNS);

    printf("[Step-4-pipe][%s] F_hw=%.10e F_ref=%.10e abs_err=%.3e rel_err=%.3e\n",
           cfg->tag,
           (double)hw_out,
           ref_out,
           abs_err,
           rel_err);

    printf("[Step-4-pipe][%s] total=%lu ticks avg=%lu ticks/run\n",
           cfg->tag,
           total_ticks,
           (unsigned long)(total_ticks / NUM_RUNS));

#endif
}

int main(void) {

    /* Reused buffer sized for largest supported case (C3). */
    static float xbuf[MAX_VECTOR_LEN];

    /* Active test cases plus final-assessment compatibility case. */
    const case_cfg_t cases[] = {
        {"C2", 2041, 1.0f / 8.0f},
        {"C3", 65281, 1.0f / 256.0f},
        {"C4", CASE4_LEN, -1.0f},
    };

    const int case_count =
        (int)(sizeof(cases) / sizeof(cases[0]));

    printf("Task7 software run started. tick_hz=%d\n",
           ALT_SYS_CLK_TICKS_PER_SEC);

#if TASK7_MODE == 5
    printf("CI opcode: fsum_pipe=%u\n", (unsigned)CI_STEP8_PIPE_BASE_N);
#endif

    for (int i = 0; i < case_count; i++) {
        run_case(&cases[i], xbuf);
    }

    printf("\nTask7 software run finished.\n");

    return 0;
}
