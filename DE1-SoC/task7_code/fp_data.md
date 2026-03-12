### CORDIC_ITER_PER_CYCLE = 1
FX_W: 40
FX_FRAC: 22
CORIDC_W: 28
CORDIC_FRAC: 22
CORDIC_ITER: 18
CORDIC_ITER_PER_CYCLE: 1

////////////////////////////////////////////

////////////////////////////////////////////

### CORDIC_ITER_PER_CYCLE = 3
///////////////////////////////////////
latency = 5 cycles
===== Case1 STEP=5 =====
Vector length (N) = 52
Total ticks = 25
Average ticks = 2
Result f(x) = 170105568.000000

---- Accelerator Profiling ----
mul ticks = 1 (1560 calls)
add ticks = 0 (520 calls)
cos ticks = 0 (520 calls)

---- Latency (ticks per operation) ----
FP MUL latency â‰ˆ 0.000641 ticks
FP ADD latency â‰ˆ 0.000000 ticks
FP COS latency â‰ˆ 0.000000 ticks

===== Case2 STEP=1/8 =====
Vector length (N) = 2041
Total ticks = 1011
Average ticks = 101
Result f(x) = 6627432960.000000

---- Accelerator Profiling ----
mul ticks = 61 (61230 calls)
add ticks = 15 (20410 calls)
cos ticks = 21 (20410 calls)

---- Latency (ticks per operation) ----
FP MUL latency â‰ˆ 0.000996 ticks
FP ADD latency â‰ˆ 0.000735 ticks
FP COS latency â‰ˆ 0.001029 ticks

===== Case3 STEP=1/256 =====
Vector length (N) = 65281
Total ticks = 33725
Average ticks = 3372
Result f(x) = 211932413952.000000

---- Accelerator Profiling ----
mul ticks = 1812 (1958430 calls)
add ticks = 612 (652810 calls)
cos ticks = 657 (652810 calls)

---- Latency (ticks per operation) ----
FP MUL latency â‰ˆ 0.000925 ticks
FP ADD latency â‰ˆ 0.000937 ticks
FP COS latency â‰ˆ 0.001006 ticks

===== Case4 random input =====
Vector length (N) = 2323
Total ticks = 1232
Average ticks = 123
Result f(x) = 7668610048.000000

===== Single Operation Latency =====
HW MUL avg ticks = 0.000540
HW ADD avg ticks = 0.000540
HW COS avg ticks = 0.000610

Latency = 3 cycles
////////////////////////////////////////////
===== Case1 STEP=5 =====
Vector length (N) = 52
Total ticks = 25
Average ticks = 2
Result f(x) = 170105568.000000

---- Accelerator Profiling ----
mul ticks = 0 (1560 calls)
add ticks = 0 (520 calls)
cos ticks = 1 (520 calls)

---- Latency (ticks per operation) ----
FP MUL latency â‰ˆ 0.000000 ticks
FP ADD latency â‰ˆ 0.000000 ticks
FP COS latency â‰ˆ 0.001923 ticks

===== Case2 STEP=1/8 =====
Vector length (N) = 2041
Total ticks = 1007
Average ticks = 100
Result f(x) = 6627432960.000000

---- Accelerator Profiling ----
mul ticks = 53 (61230 calls)
add ticks = 13 (20410 calls)
cos ticks = 21 (20410 calls)

---- Latency (ticks per operation) ----
FP MUL latency â‰ˆ 0.000866 ticks
FP ADD latency â‰ˆ 0.000637 ticks
FP COS latency â‰ˆ 0.001029 ticks

===== Case3 STEP=1/256 =====
Vector length (N) = 65281
Total ticks = 33618
Average ticks = 3361
Result f(x) = 211932413952.000000

---- Accelerator Profiling ----
mul ticks = 1777 (1958430 calls)
add ticks = 607 (652810 calls)
cos ticks = 655 (652810 calls)

---- Latency (ticks per operation) ----
FP MUL latency â‰ˆ 0.000907 ticks
FP ADD latency â‰ˆ 0.000930 ticks
FP COS latency â‰ˆ 0.001003 ticks

===== Case4 random input =====
Vector length (N) = 2323
Total ticks = 1228
Average ticks = 122
Result f(x) = 7668610048.000000

===== Single Operation Latency =====
HW MUL avg ticks = 0.000500
HW ADD avg ticks = 0.000510
HW COS avg ticks = 0.000600
////////////////////////////////////////////

latency = 2cycles
===== Case1 STEP=5 =====
Vector length (N) = 52
Total ticks = 25
Average ticks = 2
Result f(x) = 165445600.000000

---- Accelerator Profiling ----
mul ticks = 1 (1560 calls)
add ticks = 1 (520 calls)
cos ticks = 2 (520 calls)

---- Latency (ticks per operation) ----
FP MUL latency â‰ˆ 0.000641 ticks
FP ADD latency â‰ˆ 0.001923 ticks
FP COS latency â‰ˆ 0.003846 ticks

===== Case2 STEP=1/8 =====
Vector length (N) = 2041
Total ticks = 1005
Average ticks = 100
Result f(x) = 6622859776.000000

---- Accelerator Profiling ----
mul ticks = 54 (61230 calls)
add ticks = 27 (20410 calls)
cos ticks = 15 (20410 calls)

---- Latency (ticks per operation) ----
FP MUL latency â‰ˆ 0.000882 ticks
FP ADD latency â‰ˆ 0.001323 ticks
FP COS latency â‰ˆ 0.000735 ticks

===== Case3 STEP=1/256 =====
Vector length (N) = 65281
Total ticks = 33568
Average ticks = 3356
Result f(x) = 211929825280.000000

---- Accelerator Profiling ----
mul ticks = 1646 (1958430 calls)
add ticks = 602 (652810 calls)
cos ticks = 639 (652810 calls)

---- Latency (ticks per operation) ----
FP MUL latency â‰ˆ 0.000840 ticks
FP ADD latency â‰ˆ 0.000922 ticks
FP COS latency â‰ˆ 0.000979 ticks

===== Case4 random input =====
Vector length (N) = 2323
Total ticks = 1225
Average ticks = 122
Result f(x) = 5296363008.000000

===== Single Operation Latency =====
HW MUL avg ticks = 0.000480
HW ADD avg ticks = 0.000490
HW COS avg ticks = 0.000600

///////////////////////////////////////
latency = 1cycles

===== Case1 STEP=5 =====
Vector length (N) = 52
Total ticks = 25
Average ticks = 2
Result f(x) = 165445600.000000

---- Accelerator Profiling ----
mul ticks = 2 (1560 calls)
add ticks = 0 (520 calls)
cos ticks = 0 (520 calls)

---- Latency (ticks per operation) ----
FP MUL latency â‰ˆ 0.001282 ticks
FP ADD latency â‰ˆ 0.000000 ticks
FP COS latency â‰ˆ 0.000000 ticks

===== Case2 STEP=1/8 =====
Vector length (N) = 2041
Total ticks = 1004
Average ticks = 100
Result f(x) = 6622859776.000000

---- Accelerator Profiling ----
mul ticks = 58 (61230 calls)
add ticks = 17 (20410 calls)
cos ticks = 23 (20410 calls)

---- Latency (ticks per operation) ----
FP MUL latency â‰ˆ 0.000947 ticks
FP ADD latency â‰ˆ 0.000833 ticks
FP COS latency â‰ˆ 0.001127 ticks

===== Case3 STEP=1/256 =====
Vector length (N) = 65281
Total ticks = 33513
Average ticks = 3351
Result f(x) = 211929825280.000000

---- Accelerator Profiling ----
mul ticks = 1634 (1958430 calls)
add ticks = 589 (652810 calls)
cos ticks = 609 (652810 calls)

---- Latency (ticks per operation) ----
FP MUL latency â‰ˆ 0.000834 ticks
FP ADD latency â‰ˆ 0.000902 ticks
FP COS latency â‰ˆ 0.000933 ticks

===== Case4 random input =====
Vector length (N) = 2323
Total ticks = 1224
Average ticks = 122
Result f(x) = 5296363008.000000

===== Single Operation Latency =====
HW MUL avg ticks = 0.000460
HW ADD avg ticks = 0.000460
HW COS avg ticks = 0.000610