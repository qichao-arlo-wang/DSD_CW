set_global_assignment -entity "custom_fp_sub" -library "lib_custom_fp_sub" -name IP_TOOL_NAME "altera_fp_functions"
set_global_assignment -entity "custom_fp_sub" -library "lib_custom_fp_sub" -name IP_TOOL_VERSION "23.1"
set_global_assignment -entity "custom_fp_sub" -library "lib_custom_fp_sub" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_custom_fp_sub" -name SPD_FILE [file join $::quartus(sip_path) "custom_fp_sub.spd"]

set_global_assignment -library "lib_custom_fp_sub" -name MISC_FILE [file join $::quartus(sip_path) "custom_fp_sub_sim/custom_fp_sub.vo"]
