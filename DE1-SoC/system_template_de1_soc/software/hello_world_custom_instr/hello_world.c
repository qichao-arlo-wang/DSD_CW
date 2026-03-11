#include <system.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>

#include "sys/alt_alarm.h"


/*
 * Task 7b/7c software driver.
 *
 * IMPORTANT:
 *   The CI macro names below depend on the generated BSP (system.h).
 *   If your names differ, keep the wrapper names and only change the mappings.
 *   If ADD/SUB is configured as an extended CI in Platform Designer, define
 *   CI_STEP2_ADD(a_bits,b_bits) manually to force add mode (n=0).
 */

/* ----- Step-2: fp32 mul CI ----- */
#ifndef CI_STEP2_MUL
#if defined(ALT_CI_TASK7_FP_MUL_0)
#define CI_STEP2_MUL(a_bits, b_bits) ALT_CI_TASK7_FP_MUL_0((a_bits), (b_bits))
#elif defined(ALT_CI_TASK7_CI_FP32_MUL_0)
#define CI_STEP2_MUL(a_bits, b_bits) ALT_CI_TASK7_CI_FP32_MUL_0((a_bits), (b_bits))
#elif defined(ALT_CI_FP32_MUL_0)
#define CI_STEP2_MUL(a_bits, b_bits) ALT_CI_FP32_MUL_0((a_bits), (b_bits))
#elif defined(ALT_CI_MUL_0)
#define CI_STEP2_MUL(a_bits, b_bits) ALT_CI_MUL_0((a_bits), (b_bits))
#endif
#endif
/* ----- Step-2: fp32 add/sub CI (configured as add in this SW) ----- */
#ifndef CI_STEP2_ADD
#if defined(ALT_CI_TASK7_FP_ADD_SUB_0)
#define CI_STEP2_ADD(a_bits, b_bits) ALT_CI_TASK7_FP_ADD_SUB_0(0, (a_bits), (b_bits))
#elif defined(ALT_CI_TASK7_CI_FP32_ADDSUB_0)
#define CI_STEP2_ADD(a_bits, b_bits) ALT_CI_TASK7_CI_FP32_ADDSUB_0((a_bits), (b_bits))
#elif defined(ALT_CI_FP32_ADDSUB_0)
#define CI_STEP2_ADD(a_bits, b_bits) ALT_CI_FP32_ADDSUB_0((a_bits), (b_bits))
#elif defined(ALT_CI_FP32_ADD_0)
#define CI_STEP2_ADD(a_bits, b_bits) ALT_CI_FP32_ADD_0((a_bits), (b_bits))
#endif
#endif
/* ----- Step-2: cos CI ----- */
#ifndef CI_STEP2_COS
#if defined(ALT_CI_TASK7_CI_COS_ONLY_0)
#define CI_STEP2_COS(a_bits, b_bits) ALT_CI_TASK7_CI_COS_ONLY_0((a_bits), (b_bits))
#elif defined(ALT_CI_COS_ONLY_0)
#define CI_STEP2_COS(a_bits, b_bits) ALT_CI_COS_ONLY_0((a_bits), (b_bits))
#endif
#endif

/* ----- Step-3: single f(x) CI ----- */
static inline uint32_t f32_to_u32(float x);
static inline float u32_to_f32(uint32_t x);

#ifndef CI_STEP3_F
#if defined(ALT_CI_TASK7_CI_F_SINGLE_0)
#define CI_STEP3_F(a_bits, b_bits) ALT_CI_TASK7_CI_F_SINGLE_0((a_bits), (b_bits))
#elif defined(ALT_CI_F_SINGLE_0)
#define CI_STEP3_F(a_bits, b_bits) ALT_CI_F_SINGLE_0((a_bits), (b_bits))
#endif
#endif

#if !defined(CI_STEP2_MUL) || !defined(CI_STEP2_ADD) || !defined(CI_STEP2_COS)
#error "Missing CI mapping. Define CI_STEP2_MUL/CI_STEP2_ADD/CI_STEP2_COS to BSP macros in this file."
#endif

#ifndef CI_STEP3_F
#define CI_STEP3_F_IS_SW_FALLBACK 1
static inline uint32_t ci_step3_f_sw_fallback(uint32_t a_bits) {
    const float x = u32_to_f32(a_bits);
    const float t = (x - 128.0f) * (1.0f / 128.0f);
    const float fx = 0.5f * x + x * x * x * cosf(t);
    return f32_to_u32(fx);
}
#define CI_STEP3_F(a_bits, b_bits) ci_step3_f_sw_fallback((a_bits))
#else
#define CI_STEP3_F_IS_SW_FALLBACK 0
#endif
typedef struct {
    const char *name;
    int denom;
    int stride;
    int max_numer;
} test_case_t;

typedef struct {
    uint64_t total_ticks;
    uint64_t mul_ticks;
    uint64_t add_ticks;
    uint64_t cos_ticks;
    uint32_t mul_calls;
    uint32_t add_calls;
    uint32_t cos_calls;
    uint32_t step3_calls;
} timing_acc_t;

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

static uint64_t g_tick_hz = 0;

static uint64_t ticks_now(void) {
    return (uint64_t)alt_nticks();
}

static uint64_t ticks_hz(void) {
    return (uint64_t)alt_ticks_per_second();
}

static int timer_init(void) {
    g_tick_hz = ticks_hz();
    return (g_tick_hz == 0) ? -1 : 0;
}

static double ticks_to_ms(uint64_t ticks) {
    if (g_tick_hz == 0) {
        return 0.0;
    }
    return ((double)ticks * 1000.0) / (double)g_tick_hz;
}

static inline uint32_t ci_step2_mul_bits(uint32_t a_bits, uint32_t b_bits, timing_acc_t *acc) {
    const uint64_t t0 = ticks_now();
    const uint32_t out = (uint32_t)CI_STEP2_MUL(a_bits, b_bits);
    acc->mul_ticks += (ticks_now() - t0);
    acc->mul_calls++;
    return out;
}

static inline uint32_t ci_step2_add_bits(uint32_t a_bits, uint32_t b_bits, timing_acc_t *acc) {
    const uint64_t t0 = ticks_now();
    const uint32_t out = (uint32_t)CI_STEP2_ADD(a_bits, b_bits);
    acc->add_ticks += (ticks_now() - t0);
    acc->add_calls++;
    return out;
}

static inline uint32_t ci_step2_cos_bits(uint32_t a_bits, timing_acc_t *acc) {
    const uint64_t t0 = ticks_now();
    const uint32_t out = (uint32_t)CI_STEP2_COS(a_bits, 0u);
    acc->cos_ticks += (ticks_now() - t0);
    acc->cos_calls++;
    return out;
}

static inline uint32_t ci_step3_f_bits(uint32_t a_bits, timing_acc_t *acc) {
    const uint64_t t0 = ticks_now();
    const uint32_t out = (uint32_t)CI_STEP3_F(a_bits, 0u);
    acc->total_ticks += (ticks_now() - t0);
    acc->step3_calls++;
    return out;
}

/*
 * Step-2 path:
 *   f(x) = 0.5*x + x^3*cos((x-128)/128)
 * Scheduling:
 *   - use MUL CI for x^2, x^3, and x^3*cos(...)
 *   - use COS CI for cos()
 *   - use ADD/SUB CI for final accumulation
 *   - scalar constants transform (x-128)/128 and 0.5*x are done in software
 */
static float eval_fx_step2(float x, timing_acc_t *acc) {
    const uint32_t x_bits = f32_to_u32(x);
    const float angle = (x - 128.0f) * (1.0f / 128.0f);
    const uint32_t angle_bits = f32_to_u32(angle);
    const uint32_t half_bits = f32_to_u32(0.5f * x);

    const uint32_t x2_bits = ci_step2_mul_bits(x_bits, x_bits, acc);
    const uint32_t x3_bits = ci_step2_mul_bits(x2_bits, x_bits, acc);
    const uint32_t cos_bits = ci_step2_cos_bits(angle_bits, acc);
    const uint32_t term_bits = ci_step2_mul_bits(x3_bits, cos_bits, acc);
    const uint32_t fx_bits = ci_step2_add_bits(half_bits, term_bits, acc);

    return u32_to_f32(fx_bits);
}

static float eval_fx_step3(float x, timing_acc_t *acc) {
    const uint32_t x_bits = f32_to_u32(x);
    return u32_to_f32(ci_step3_f_bits(x_bits, acc));
}

static double ref_fx_double(double x) {
    const double t = (x - 128.0) / 128.0;
    return 0.5 * x + x * x * x * cos(t);
}

static double run_ref_case(const test_case_t *tc) {
    double sum = 0.0;
    int k;
    for (k = 0; k <= tc->max_numer; k += tc->stride) {
        const double x = (double)k / (double)tc->denom;
        sum += ref_fx_double(x);
    }
    return sum;
}

static double run_step2_case(const test_case_t *tc, timing_acc_t *acc) {
    double sum = 0.0;
    int k;
    for (k = 0; k <= tc->max_numer; k += tc->stride) {
        const float x = (float)k / (float)tc->denom;
        const uint64_t t0 = ticks_now();
        const float fx = eval_fx_step2(x, acc);
        acc->total_ticks += (ticks_now() - t0);
        sum += (double)fx;
    }
    return sum;
}

static double run_step3_case(const test_case_t *tc, timing_acc_t *acc) {
    double sum = 0.0;
    int k;
    for (k = 0; k <= tc->max_numer; k += tc->stride) {
        const float x = (float)k / (float)tc->denom;
        const float fx = eval_fx_step3(x, acc);
        sum += (double)fx;
    }
    return sum;
}

static void print_step2_report(const test_case_t *tc, const timing_acc_t *acc, double f_hw, double f_ref) {
    const double abs_err = fabs(f_hw - f_ref);
    const double rel_err = (fabs(f_ref) > 0.0) ? (abs_err / fabs(f_ref)) : 0.0;

    const double t_total_ms = ticks_to_ms(acc->total_ticks);
    const double t_mul_ms = ticks_to_ms(acc->mul_ticks);
    const double t_add_ms = ticks_to_ms(acc->add_ticks);
    const double t_cos_ms = ticks_to_ms(acc->cos_ticks);
    const double t_acc_ms = t_mul_ms + t_add_ms + t_cos_ms;

    printf("[Step-2][%s] F_hw=%0.10e F_ref=%0.10e abs_err=%0.3e rel_err=%0.3e\n",
           tc->name, f_hw, f_ref, abs_err, rel_err);
    printf("[Step-2][%s] total=%0.3f ms accel_sum=%0.3f ms overhead=%0.3f ms\n",
           tc->name, t_total_ms, t_acc_ms, t_total_ms - t_acc_ms);
    printf("[Step-2][%s] mul=%0.3f ms (%lu calls), add=%0.3f ms (%lu calls), cos=%0.3f ms (%lu calls)\n",
           tc->name,
           t_mul_ms, (unsigned long)acc->mul_calls,
           t_add_ms, (unsigned long)acc->add_calls,
           t_cos_ms, (unsigned long)acc->cos_calls);
}

static void print_step3_report(const test_case_t *tc, const timing_acc_t *acc, double f_hw, double f_ref) {
    const double abs_err = fabs(f_hw - f_ref);
    const double rel_err = (fabs(f_ref) > 0.0) ? (abs_err / fabs(f_ref)) : 0.0;

    printf("[Step-3][%s] F_hw=%0.10e F_ref=%0.10e abs_err=%0.3e rel_err=%0.3e\n",
           tc->name, f_hw, f_ref, abs_err, rel_err);
    printf("[Step-3][%s] total=%0.3f ms (%lu calls)\n",
           tc->name, ticks_to_ms(acc->total_ticks), (unsigned long)acc->step3_calls);
}

int main(void) {
    int i;
    const test_case_t cases[] = {
        {"C1", 1, 5, 255},
        {"C2", 8, 1, 255 * 8},
        {"C3", 256, 1, 255 * 256}
    };
    const int n_cases = (int)(sizeof(cases) / sizeof(cases[0]));

    if (timer_init() != 0) {
        printf("ERROR: timer init failed. Check timestamp/sys clock configuration in BSP.\n");
        return 1;
    }

    printf("Task7b/7c software run started. tick_hz=%lu\n", (unsigned long)g_tick_hz);

    for (i = 0; i < n_cases; ++i) {
        timing_acc_t step2_acc = {0};
        timing_acc_t step3_acc = {0};
        const double ref_sum = run_ref_case(&cases[i]);
        const double step2_sum = run_step2_case(&cases[i], &step2_acc);
        const double step3_sum = run_step3_case(&cases[i], &step3_acc);

        print_step2_report(&cases[i], &step2_acc, step2_sum, ref_sum);
        print_step3_report(&cases[i], &step3_acc, step3_sum, ref_sum);
        printf("\n");
    }

    printf("Task7b/7c software run finished.\n");
    return 0;
}





