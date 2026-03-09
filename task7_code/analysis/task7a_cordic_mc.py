#!/usr/bin/env python3
"""
Task 7a Monte-Carlo analysis for CORDIC cosine.

This script sweeps CORDIC iterations and fixed-point fractional bits, then estimates:
- MSE against float32 cos reference
- 95% confidence interval for the mean squared error

Requirement from coursework:
upper 95% CI bound of MSE < 2.4e-11 for x ~ U[-1, 1].
"""

import argparse
import math
import random
import statistics
import struct
from typing import List, Tuple

MSE_LIMIT = 2.4e-11


def to_float32(x: float) -> float:
    return struct.unpack("!f", struct.pack("!f", x))[0]


def cordic_cos(theta: float, n_iter: int, frac: int) -> float:
    scale = 1 << frac

    k_gain = 1.0
    for i in range(n_iter):
        k_gain *= 1.0 / math.sqrt(1.0 + 2.0 ** (-2 * i))

    x = int(round(k_gain * scale))
    y = 0
    z = int(round(theta * scale))

    atan_table = [int(round(math.atan(2.0 ** -i) * scale)) for i in range(n_iter)]

    for i in range(n_iter):
        if z >= 0:
            x, y, z = x - (y >> i), y + (x >> i), z - atan_table[i]
        else:
            x, y, z = x + (y >> i), y - (x >> i), z + atan_table[i]

    return x / scale


def mse_with_ci(samples: List[float]) -> Tuple[float, float, float]:
    n = len(samples)
    mean_v = statistics.fmean(samples)
    if n < 2:
        return mean_v, mean_v, mean_v

    stdev_v = statistics.stdev(samples)
    half = 1.96 * stdev_v / math.sqrt(n)
    return mean_v, mean_v - half, mean_v + half


def evaluate_cfg(n_iter: int, frac: int, n_samples: int, seed: int) -> Tuple[float, float, float]:
    random.seed(seed)
    sq_err = []
    for _ in range(n_samples):
        theta = random.uniform(-1.0, 1.0)
        ref = to_float32(math.cos(theta))
        est = cordic_cos(theta, n_iter=n_iter, frac=frac)
        d = est - ref
        sq_err.append(d * d)
    return mse_with_ci(sq_err)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=50000, help="Monte-Carlo sample count")
    ap.add_argument("--seed", type=int, default=7, help="Random seed")
    ap.add_argument("--iters", type=int, nargs="+", default=[12, 14, 16, 18, 20, 22, 24])
    ap.add_argument("--fracs", type=int, nargs="+", default=[20, 22, 24, 26, 28, 30, 32, 34])
    args = ap.parse_args()

    print("CORDIC sweep for Task 7a")
    print(f"Samples={args.samples}, seed={args.seed}, limit={MSE_LIMIT:.3e}")
    print("iter frac mse ci95_low ci95_high pass")

    best = None

    for frac in args.fracs:
        for n_iter in args.iters:
            mse, lo, hi = evaluate_cfg(n_iter, frac, args.samples, args.seed)
            passed = hi < MSE_LIMIT
            print(f"{n_iter:>4} {frac:>4} {mse:.3e} {lo:.3e} {hi:.3e} {'YES' if passed else 'NO'}")

            if passed:
                score = (n_iter, frac)
                if best is None or score < best[0]:
                    best = (score, (mse, lo, hi))

    if best is None:
        print("\nNo configuration met the target bound.")
    else:
        (n_iter, frac), (mse, lo, hi) = best
        print("\nBest passing configuration (minimum iterations, then minimum frac bits):")
        print(f"n_iter={n_iter}, frac={frac}, mse={mse:.3e}, ci95=[{lo:.3e}, {hi:.3e}]")


if __name__ == "__main__":
    main()
