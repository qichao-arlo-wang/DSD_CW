#include <system.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>

#include "sys/alt_alarm.h"

/*
 * Global run selector:
 *   0 -> auto (run every available step)
 *   2 -> Step-2 only
 *   3 -> Step-3 only
 */
#ifndef TASK7_RUN_STEP
#define TASK7_RUN_STEP 2
#endif

/* Intel floating-point CI opcode selector. */
#ifndef CI_NIOS_FP_OP_MUL
#define CI_NIOS_FP_OP_MUL 0u
#endif

#ifndef CI_NIOS_FP_OP_ADD
#define CI_NIOS_FP_OP_ADD 1u
#endif

#define RUN_STEP2_SELECTED ((TASK7_RUN_STEP == 0) || (TASK7_RUN_STEP == 2))
#define RUN_STEP3_SELECTED ((TASK7_RUN_STEP == 0) || (TASK7_RUN_STEP == 3))

#if defined(ALT_CI_NIOS_CUSTOM_INSTR_FLOATING_POINT_0) && defined(ALT_CI_TASK7_CI_COS_ONLY_0)
#define STEP2_CI_AVAILABLE 1
#define CI_STEP2_MUL(a_bits, b_bits) ALT_CI_NIOS_CUSTOM_INSTR_FLOATING_POINT_0(CI_NIOS_FP_OP_MUL, (a_bits), (b_bits))
#define CI_STEP2_ADD(a_bits, b_bits) ALT_CI_NIOS_CUSTOM_INSTR_FLOATING_POINT_0(CI_NIOS_FP_OP_ADD, (a_bits), (b_bits))
#define CI_STEP2_COS(a_bits, b_bits) ALT_CI_TASK7_CI_COS_ONLY_0((a_bits), (b_bits))
#else
#define STEP2_CI_AVAILABLE 0
#endif

#if defined(ALT_CI_TASK7_CI_F_SINGLE_0)
#define STEP3_CI_AVAILABLE 1
#define CI_STEP3_F(a_bits, b_bits) ALT_CI_TASK7_CI_F_SINGLE_0((a_bits), (b_bits))
#elif defined(ALT_CI_F_SINGLE_0)
#define STEP3_CI_AVAILABLE 1
#define CI_STEP3_F(a_bits, b_bits) ALT_CI_F_SINGLE_0((a_bits), (b_bits))
#else
#define STEP3_CI_AVAILABLE 0
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

static int timer_init(void) {
    g_tick_hz = (uint64_t)alt_ticks_per_second();
    return (g_tick_hz == 0) ? -1 : 0;
}

#if STEP2_CI_AVAILABLE
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

static void print_step2_report(const test_case_t *tc, const timing_acc_t *acc, double f_hw, double f_ref) {
    const double abs_err = fabs(f_hw - f_ref);
    const double rel_err = (fabs(f_ref) > 0.0) ? (abs_err / fabs(f_ref)) : 0.0;
    const uint64_t t_acc = acc->mul_ticks + acc->add_ticks + acc->cos_ticks;

    printf("[Step-2][%s] F_hw=%0.10e F_ref=%0.10e abs_err=%0.3e rel_err=%0.3e\n",
           tc->name, f_hw, f_ref, abs_err, rel_err);
    printf("[Step-2][%s] total=%llu ticks accel_sum=%llu ticks overhead=%llu ticks\n",
           tc->name,
           (unsigned long long)acc->total_ticks,
           (unsigned long long)t_acc,
           (unsigned long long)(acc->total_ticks - t_acc));
    printf("[Step-2][%s] mul=%llu ticks (%lu calls), add=%llu ticks (%lu calls), cos=%llu ticks (%lu calls)\n",
           tc->name,
           (unsigned long long)acc->mul_ticks, (unsigned long)acc->mul_calls,
           (unsigned long long)acc->add_ticks, (unsigned long)acc->add_calls,
           (unsigned long long)acc->cos_ticks, (unsigned long)acc->cos_calls);
}
#endif

#if STEP3_CI_AVAILABLE
static inline uint32_t ci_step3_f_bits(uint32_t a_bits, timing_acc_t *acc) {
    const uint64_t t0 = ticks_now();
    const uint32_t out = (uint32_t)CI_STEP3_F(a_bits, 0u);
    acc->total_ticks += (ticks_now() - t0);
    acc->step3_calls++;
    return out;
}

static float eval_fx_step3(float x, timing_acc_t *acc) {
    const uint32_t x_bits = f32_to_u32(x);
    return u32_to_f32(ci_step3_f_bits(x_bits, acc));
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

static void print_step3_report(const test_case_t *tc, const timing_acc_t *acc, double f_hw, double f_ref) {
    const double abs_err = fabs(f_hw - f_ref);
    const double rel_err = (fabs(f_ref) > 0.0) ? (abs_err / fabs(f_ref)) : 0.0;

    printf("[Step-3][%s] F_hw=%0.10e F_ref=%0.10e abs_err=%0.3e rel_err=%0.3e\n",
           tc->name, f_hw, f_ref, abs_err, rel_err);
    printf("[Step-3][%s] total=%llu ticks (%lu calls)\n",
           tc->name,
           (unsigned long long)acc->total_ticks,
           (unsigned long)acc->step3_calls);
}
#endif

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

int main(void) {
    int i;
    int run_step2;
    int run_step3;
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
    printf("TASK7_RUN_STEP=%d (0:auto,2:step2,3:step3)\n", TASK7_RUN_STEP);

    if (!STEP2_CI_AVAILABLE && !STEP3_CI_AVAILABLE) {
        printf("ERROR: both Step-2 and Step-3 custom instructions are unavailable.\n");
        printf("ERROR: need ALT_CI_NIOS_CUSTOM_INSTR_FLOATING_POINT_0 + ALT_CI_TASK7_CI_COS_ONLY_0 for Step-2, and ALT_CI_TASK7_CI_F_SINGLE_0 or ALT_CI_F_SINGLE_0 for Step-3.\n");
        return 1;
    }

    run_step2 = (RUN_STEP2_SELECTED && STEP2_CI_AVAILABLE) ? 1 : 0;
    run_step3 = (RUN_STEP3_SELECTED && STEP3_CI_AVAILABLE) ? 1 : 0;

    if (RUN_STEP2_SELECTED && !STEP2_CI_AVAILABLE) {
        printf("INFO: Step-2 selected but required CI macros are missing in system.h.\n");
    }
    if (RUN_STEP3_SELECTED && !STEP3_CI_AVAILABLE) {
        printf("INFO: Step-3 selected but CI macro is missing in system.h.\n");
    }
    if (!run_step2 && !run_step3) {
        printf("ERROR: no runnable step is available with current TASK7_RUN_STEP and system.h macros.\n");
        return 1;
    }

    for (i = 0; i < n_cases; ++i) {
        timing_acc_t step2_acc = {0};
        timing_acc_t step3_acc = {0};
        const double ref_sum = run_ref_case(&cases[i]);

#if STEP2_CI_AVAILABLE
        if (run_step2) {
            const double step2_sum = run_step2_case(&cases[i], &step2_acc);
            print_step2_report(&cases[i], &step2_acc, step2_sum, ref_sum);
        }
#endif

#if STEP3_CI_AVAILABLE
        if (run_step3) {
            const double step3_sum = run_step3_case(&cases[i], &step3_acc);
            print_step3_report(&cases[i], &step3_acc, step3_sum, ref_sum);
        }
#endif

        printf("\n");
    }

    printf("Task7b/7c software run finished.\n");
    return 0;
}

