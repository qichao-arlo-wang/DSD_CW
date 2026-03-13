#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/times.h>
#include <unistd.h>

#include "io.h"
#include "system.h"

#if defined(ALT_CPU_DCACHE_SIZE) && (ALT_CPU_DCACHE_SIZE > 0)
#include "sys/alt_cache.h"
#endif

/*
 * Task 8 software-only entry for MM + DMA architecture.
 *
 * This file intentionally keeps only Task 8 flow:
 *   1) Build input vector X
 *   2) Program MM accelerator (LEN/CLEAR/START)
 *   3) Start mSGDMA MM->ST transfer of X (fp32 stream)
 *   4) Poll done and read RESULT
 *   5) Compare against software double reference
 */

#define NUM_RUNS 10
#define MAX_VECTOR_LEN 70000

#define CASE4_LEN 2323
#define CASE4_SEED 334u
#define CASE4_MAXVAL 255.0f

/* ------------------------- Base address selection ------------------------- */
#if defined(TASK8_MM_FSUM_ACCEL_0_BASE)
#define TASK8_ACCEL_BASE TASK8_MM_FSUM_ACCEL_0_BASE
#elif defined(TASK8_FSUM_ACCEL_0_BASE)
#define TASK8_ACCEL_BASE TASK8_FSUM_ACCEL_0_BASE
#elif defined(TASK8_ACCEL_0_BASE)
#define TASK8_ACCEL_BASE TASK8_ACCEL_0_BASE
#else
#error "Cannot find Task8 accelerator base in system.h. Map TASK8_ACCEL_BASE to your CSR slave base."
#endif

#if defined(MSGDMA_0_CSR_BASE)
#define MSGDMA_CSR_BASE MSGDMA_0_CSR_BASE
#elif defined(MSGDMA_MM_TO_ST_0_CSR_BASE)
#define MSGDMA_CSR_BASE MSGDMA_MM_TO_ST_0_CSR_BASE
#elif defined(DMA_0_CSR_BASE)
#define MSGDMA_CSR_BASE DMA_0_CSR_BASE
#else
#error "Cannot find mSGDMA CSR base in system.h. Map MSGDMA_CSR_BASE to your DMA CSR base."
#endif

#if defined(MSGDMA_0_DESCRIPTOR_SLAVE_BASE)
#define MSGDMA_DESC_BASE MSGDMA_0_DESCRIPTOR_SLAVE_BASE
#elif defined(MSGDMA_MM_TO_ST_0_DESCRIPTOR_SLAVE_BASE)
#define MSGDMA_DESC_BASE MSGDMA_MM_TO_ST_0_DESCRIPTOR_SLAVE_BASE
#elif defined(DMA_0_DESCRIPTOR_SLAVE_BASE)
#define MSGDMA_DESC_BASE DMA_0_DESCRIPTOR_SLAVE_BASE
#else
#error "Cannot find mSGDMA descriptor base in system.h. Map MSGDMA_DESC_BASE to your descriptor slave base."
#endif

/* --------------------- Task8 MM accelerator registers --------------------- */
#define ACCEL_REG_CTRL       0x00u
#define ACCEL_REG_STATUS     0x04u
#define ACCEL_REG_LEN        0x08u
#define ACCEL_REG_RESULT     0x0Cu
#define ACCEL_REG_CYCLES     0x10u
#define ACCEL_REG_ACCEPTED   0x14u
#define ACCEL_REG_PROCESSED  0x18u

#define ACCEL_CTRL_START     (1u << 0)
#define ACCEL_CTRL_CLEAR     (1u << 1)
#define ACCEL_CTRL_IRQ_EN    (1u << 2)

#define ACCEL_ST_BUSY        (1u << 0)
#define ACCEL_ST_DONE        (1u << 1)
#define ACCEL_ST_ERR         (1u << 2)

/* ---------------------- mSGDMA CSR / descriptor regs --------------------- */
/*
 * Note:
 *   Offsets below follow Intel mSGDMA dispatcher map used by standard
 *   descriptor mode. If your generated IP uses different map/macros, update
 *   these constants to match your BSP headers.
 */
#define MSGDMA_CSR_STATUS            0x00u
#define MSGDMA_CSR_CONTROL           0x04u

#define MSGDMA_CSR_STATUS_BUSY       (1u << 0)
#define MSGDMA_CSR_CONTROL_RESET     (1u << 1)

#define MSGDMA_DESC_READ_ADDR_LO     0x00u
#define MSGDMA_DESC_WRITE_ADDR_LO    0x04u
#define MSGDMA_DESC_LENGTH           0x08u
#define MSGDMA_DESC_CONTROL          0x0Cu
#define MSGDMA_DESC_READ_ADDR_HI     0x14u
#define MSGDMA_DESC_WRITE_ADDR_HI    0x18u

#define MSGDMA_DESC_CTL_GO           (1u << 31)
#define MSGDMA_DESC_CTL_GEN_SOP      (1u << 8)
#define MSGDMA_DESC_CTL_GEN_EOP      (1u << 9)

typedef struct {
    const char *tag;
    int len;
    float step; /* step >= 0 => arithmetic vector, step < 0 => random vector */
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

static inline void accel_write(uint32_t reg, uint32_t val) {
    IOWR_32DIRECT(TASK8_ACCEL_BASE, reg, val);
}

static inline uint32_t accel_read(uint32_t reg) {
    return IORD_32DIRECT(TASK8_ACCEL_BASE, reg);
}

static void msgdma_reset(void) {
    IOWR_32DIRECT(MSGDMA_CSR_BASE, MSGDMA_CSR_CONTROL, MSGDMA_CSR_CONTROL_RESET);
    /* Allow a few cycles for reset to settle. */
    for (volatile int i = 0; i < 128; i++) {
        (void)i;
    }
}

static void msgdma_submit_mm_to_st(const void *src, uint32_t bytes) {
    uint64_t addr64 = (uint64_t)(uintptr_t)src;
    uint32_t addr_lo = (uint32_t)(addr64 & 0xFFFFFFFFu);
    uint32_t addr_hi = (uint32_t)(addr64 >> 32);

    /* Program descriptor, GO must be written last. */
    IOWR_32DIRECT(MSGDMA_DESC_BASE, MSGDMA_DESC_READ_ADDR_HI, addr_hi);
    IOWR_32DIRECT(MSGDMA_DESC_BASE, MSGDMA_DESC_WRITE_ADDR_HI, 0u);
    IOWR_32DIRECT(MSGDMA_DESC_BASE, MSGDMA_DESC_READ_ADDR_LO, addr_lo);
    IOWR_32DIRECT(MSGDMA_DESC_BASE, MSGDMA_DESC_WRITE_ADDR_LO, 0u);
    IOWR_32DIRECT(MSGDMA_DESC_BASE, MSGDMA_DESC_LENGTH, bytes);
    IOWR_32DIRECT(MSGDMA_DESC_BASE,
                  MSGDMA_DESC_CONTROL,
                  MSGDMA_DESC_CTL_GEN_SOP | MSGDMA_DESC_CTL_GEN_EOP | MSGDMA_DESC_CTL_GO);
}

static void wait_dma_idle(void) {
    while (IORD_32DIRECT(MSGDMA_CSR_BASE, MSGDMA_CSR_STATUS) & MSGDMA_CSR_STATUS_BUSY) {
        /* busy wait */
    }
}

static void generate_vector(float x[], int len, float step) {
    x[0] = 0.0f;
    for (int i = 1; i < len; i++) {
        x[i] = x[i - 1] + step;
    }
}

static void generate_random_vector(float x[], int len) {
    srand(CASE4_SEED);
    for (int i = 0; i < len; i++) {
        x[i] = ((float)rand() / (float)RAND_MAX) * CASE4_MAXVAL;
    }
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

static float run_accelerator_sum(const float x[], int len) {
    uint32_t st;

#if defined(ALT_CPU_DCACHE_SIZE) && (ALT_CPU_DCACHE_SIZE > 0)
    alt_dcache_flush((void *)x, (uint32_t)(len * (int)sizeof(float)));
#endif

    msgdma_reset();

    accel_write(ACCEL_REG_LEN, (uint32_t)len);
    accel_write(ACCEL_REG_CTRL, ACCEL_CTRL_CLEAR);
    accel_write(ACCEL_REG_CTRL, ACCEL_CTRL_START);

    msgdma_submit_mm_to_st(x, (uint32_t)(len * (int)sizeof(float)));

    wait_dma_idle();

    do {
        st = accel_read(ACCEL_REG_STATUS);
    } while ((st & ACCEL_ST_DONE) == 0u);

    if ((st & ACCEL_ST_ERR) != 0u) {
        printf("[Task8] Accelerator reported ERR status.\n");
    }

    return u32_to_f32(accel_read(ACCEL_REG_RESULT));
}

static void run_case(const case_cfg_t *cfg, float xbuf[]) {
    float hw_out = 0.0f;
    double ref_out;
    double abs_err;
    double rel_err;
    unsigned long t0;
    unsigned long t1;
    unsigned long total_ticks;
    double ms_per_run;

    if (cfg->step >= 0.0f) {
        generate_vector(xbuf, cfg->len, cfg->step);
    } else {
        generate_random_vector(xbuf, cfg->len);
    }

    ref_out = compute_fx_ref_double(xbuf, cfg->len);

    t0 = now_ticks();
    for (int k = 0; k < NUM_RUNS; k++) {
        hw_out = run_accelerator_sum(xbuf, cfg->len);
    }
    t1 = now_ticks();

    total_ticks = t1 - t0;
    ms_per_run = 1000.0 * ((double)total_ticks / (double)ALT_SYS_CLK_TICKS_PER_SEC) / (double)NUM_RUNS;

    abs_err = fabs((double)hw_out - ref_out);
    rel_err = (ref_out == 0.0) ? 0.0 : (abs_err / fabs(ref_out));

    printf("\n[Task8-MM][%s] len=%d step=%.9g runs=%d\n",
           cfg->tag,
           cfg->len,
           (double)cfg->step,
           NUM_RUNS);
    printf("[Task8-MM][%s] F_hw=%.10e F_ref=%.10e abs_err=%.3e rel_err=%.3e\n",
           cfg->tag,
           (double)hw_out,
           ref_out,
           abs_err,
           rel_err);
    printf("[Task8-MM][%s] total=%lu ticks avg=%.3f ms/run\n",
           cfg->tag,
           total_ticks,
           ms_per_run);
    printf("[Task8-MM][%s] accel_cycles=%u accepted=%u processed=%u\n",
           cfg->tag,
           (unsigned)accel_read(ACCEL_REG_CYCLES),
           (unsigned)accel_read(ACCEL_REG_ACCEPTED),
           (unsigned)accel_read(ACCEL_REG_PROCESSED));
}

int main(void) {
    static float xbuf[MAX_VECTOR_LEN];

    const case_cfg_t cases[] = {
        {"C1", 52, 5.0f},
        {"C2", 2041, 1.0f / 8.0f},
        {"C3", 65281, 1.0f / 256.0f},
        {"C4", CASE4_LEN, -1.0f},
    };
    const int case_count = (int)(sizeof(cases) / sizeof(cases[0]));

    printf("Task8 MM+DMA run started. tick_hz=%d\n", ALT_SYS_CLK_TICKS_PER_SEC);
    printf("ACCEL_BASE=0x%08X MSGDMA_CSR=0x%08X MSGDMA_DESC=0x%08X\n",
           (unsigned)TASK8_ACCEL_BASE,
           (unsigned)MSGDMA_CSR_BASE,
           (unsigned)MSGDMA_DESC_BASE);

    for (int i = 0; i < case_count; i++) {
        run_case(&cases[i], xbuf);
    }

    printf("\nTask8 MM+DMA run finished.\n");
    return 0;
}
