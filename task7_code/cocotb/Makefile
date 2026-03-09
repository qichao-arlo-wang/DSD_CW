SIM ?= verilator
TOPLEVEL_LANG ?= verilog

PWD := $(shell pwd)
RTL_DIR := $(PWD)/../rtl

VERILOG_SOURCES += $(RTL_DIR)/task7_fp32_to_fx.sv
VERILOG_SOURCES += $(RTL_DIR)/task7_fx_to_fp32.sv
VERILOG_SOURCES += $(RTL_DIR)/task7_fp32_mul_unit.sv
VERILOG_SOURCES += $(RTL_DIR)/task7_fp32_add_unit.sv
VERILOG_SOURCES += $(RTL_DIR)/task7_cordic_cos_multi_iter.sv
VERILOG_SOURCES += $(RTL_DIR)/task7_ci_f_single.sv

TOPLEVEL := task7_ci_f_single
COCOTB_TEST_MODULES := test_task7_ci

COMPILE_ARGS += -Wall -Wno-fatal -Wno-DECLFILENAME -sv

include $(shell cocotb-config --makefiles)/Makefile.sim
