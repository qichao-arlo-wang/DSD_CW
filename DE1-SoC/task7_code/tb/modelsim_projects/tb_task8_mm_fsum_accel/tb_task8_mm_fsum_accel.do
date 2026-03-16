transcript on
onerror {quit -f -code 1}
onbreak {quit -f -code 1}
if {[file exists work]} { catch {vdel -lib work -all} }
vlib work
vmap work work
vlog -work work {../../../rtl/sim_models/custom_fp_add.sv}
vlog -work work {../../../rtl/sim_models/custom_fp_mul.sv}
vlog -work work {../../../rtl/sim_models/custom_fp_sub.sv}
vlog -work work {../../../rtl/core/task7_cordic_cos_multi_iter.sv}
vlog -work work {../../../rtl/core/task7_fp_add_ip_unit.sv}
vlog -work work {../../../rtl/core/task7_fp_mul_ip_unit.sv}
vlog -work work {../../../rtl/core/task7_fp_sub_ip_unit.sv}
vlog -work work {../../../rtl/core/task7_fp32_to_fx.sv}
vlog -work work {../../../rtl/core/task7_fx_to_fp32.sv}
vlog -work work {../../../rtl/ci_step2/task7_ci_cos_only.sv}
vlog -work work {../../../rtl/ci_step2/task7_ci_fp32_add.sv}
vlog -work work {../../../rtl/ci_step2/task7_ci_fp32_mul.sv}
vlog -work work {../../../rtl/ci_step2/task7_ci_fp32_sub.sv}
vlog -work work {../../../rtl/ci_step3/task7_ci_f_single.sv}
vlog -work work {../../../rtl/task8/task8_ci_f2_accum.sv}
vlog -work work {../../../rtl/task8_mm/task8_mm_fsum_accel.sv}
vlog -work work {../../../rtl/task8_pipe/task8_cordic_cos_pipe.sv}
vlog -work work {../../../rtl/task8_pipe/task8_fp_accum_interleaved.sv}
vlog -work work {../../../rtl/task8_pipe/task8_fp_add_rr_stage.sv}
vlog -work work {../../../rtl/task8_pipe/task8_fp_mul_rr_stage.sv}
vlog -work work {../../../rtl/task8_pipe/task8_pipe_fsum_core.sv}
vlog -work work {../../../rtl/task8_pipe/task8_ci_fsum_pipe.sv}
vlog -work work {../../tb_task8_mm_fsum_accel.sv}
vsim -c work.tb_task8_mm_fsum_accel
run -all
quit -f -code 0
