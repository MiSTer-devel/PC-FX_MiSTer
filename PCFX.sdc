derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

# The column bit is sampled again before the column command.
set bulk_col_src [get_registers {emu:emu|pcfx_savestates:pcfx_savestates|pcfx_ss_engine:engine|bk_addr[0]}]
set bulk_col_dst [get_registers {emu:emu|pcfx_memory:pcfx_memory|bkq_addr[0]}]
if {[get_collection_size $bulk_col_src] != 1 || [get_collection_size $bulk_col_dst] != 1} {
	error "Bulk column hold endpoints must each match one register"
}
set_false_path -hold -from $bulk_col_src -to $bulk_col_dst

# CPU clock-enable multicycle.
# The V810 runs on ce_sck, which pcfx_clocks makes from a clk_sys toggle ANDed
# only with run, so it never fires on two clk_sys edges in a row. A CPU
# register written only on ce_sck holds for at least two clk_sys periods, and
# one read only on ce_sck samples once per two, so a path between two such
# registers has two periods. -hold 1 keeps the hold check on the launch edge.
# Left at one period:
# - registers also written on phi1 (ce_sck registered) or on every clk_sys:
#   READY/SZRQ/HLDRQ sampling, hold-data gating, idle-T1 pin registers,
#   multiplier digit registers, and register file read registers;
# - block RAMs, and the debug retire pulse;
# - every path that starts or ends outside the CPU (glue, memory, savestate).
# Savestate restore writes CPU registers between ce_sck edges, but only while
# the savestate engine owns the board and ce_sck is off; the board restarts
# several clocks after the last write, through the run/freeze handshake.
set cpu_ce_regs [get_registers -nowarn {*|NECv810:u_cpu|*}]
set cpu_fast_regs [get_registers -nowarn {
	*|NECv810:u_cpu|necv810_regfile:u_gpr|*
	*|NECv810:u_cpu|necv810_integer_engine:u_int|addend_q*
	*|NECv810:u_cpu|necv810_integer_engine:u_int|multiplicand3_q*
	*|NECv810:u_cpu|necv810_bus_engine:u_bus|ready_s_q*
	*|NECv810:u_cpu|necv810_bus_engine:u_bus|szrq_s_q*
	*|NECv810:u_cpu|necv810_bus_engine:u_bus|hldrq_s_q*
	*|NECv810:u_cpu|necv810_bus_engine:u_bus|early_*
	*|NECv810:u_cpu|hold_data_q*
	*|NECv810:u_cpu|trace_valid_o*
	*|NECv810:u_cpu|*altsyncram*
}]
set cpu_ce_regs [remove_from_collection $cpu_ce_regs $cpu_fast_regs]

if {[get_collection_size $cpu_ce_regs] == 0} {
	post_message -type error "No CPU clock-enable registers matched"
} else {
	post_message -type info "CPU clock-enable multicycle: [get_collection_size $cpu_ce_regs] registers, [get_collection_size $cpu_fast_regs] left at one period"
	set_multicycle_path -setup 2 -from $cpu_ce_regs -to $cpu_ce_regs
	set_multicycle_path -hold 1 -from $cpu_ce_regs -to $cpu_ce_regs
}
