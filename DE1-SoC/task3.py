import numpy as np

# ------------------------------------------------------------
# Task 3: Reference implementation in Python
# ------------------------------------------------------------

MAXVAL = 255.0


def generate_vector(step: float) -> np.ndarray:
    """
    Generate input vector X according to coursework definition:
    X = 0:step:255
    Values are stored as single-precision floats (float32)
    """
    # Important: include 255 if exactly reachable
    x = np.arange(0, 255 + step, step, dtype=np.float32)
    return x


def generate_random_vector(n: int, seed: int) -> np.ndarray:
    """
    Generate random vector for test case 4:
    x[i] = (rand() / RAND_MAX) * MAXVAL
    """
    rng = np.random.default_rng(seed)
    x = rng.random(n, dtype=np.float32) * np.float32(MAXVAL)
    return x


def compute_fx(x: np.ndarray) -> np.float64:
    """
    Compute:
        f(x) = sum(0.5*x + x^3 * cos((x-128)/128))

    - x is float32 (single precision)
    - cos and accumulation are done in double precision (NumPy default),
      matching Matlab/Python reference behaviour
    """
    term1 = 0.5 * x
    term2 = (x ** 3) * np.cos((x - 128.0) / 128.0)
    y = np.sum(term1 + term2)
    return y


# ------------------------------------------------------------
# Test cases (exactly as in the coursework)
# ------------------------------------------------------------

def run_task3_tests():
    test_cases = {
        "Test case 1 (step = 5)": 5.0,
        "Test case 2 (step = 1/8)": 1.0 / 8.0,
        "Test case 3 (step = 1/256)": 1.0 / 256.0,
    }

    for name, step in test_cases.items():
        x = generate_vector(step)
        y = compute_fx(x)

        print(f"{name}")
        print(f"  Vector length N = {len(x)}")
        print(f"  Result f(x)     = {y:.10e}")
        print("")

    # Test case 4 (FINAL ASSESSMENT)
    n = 2323
    seed = 334
    x = generate_random_vector(n, seed)
    y = compute_fx(x)

    print("Test case 4: random input vector")
    print(f"  Vector length N = {len(x)}")
    print(f"  Result f(x)     = {y:.10e}")
    print("")


if __name__ == "__main__":
    run_task3_tests()
