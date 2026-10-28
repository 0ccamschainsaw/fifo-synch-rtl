# Batch synthesis + implementation + timing report (no GUI)
file mkdir sim_out_timing
read_verilog [glob rtl/*.v]
read_xdc constraints/clk.xdc

# Replace with the part from your original Vivado project
synth_design -top cpu_SC -part xc7z010iclg225-1L -mode out_of_context
opt_design
place_design
route_design

report_timing_summary -file sim_out_timing/timing_summary.rpt
report_timing -max_paths 1 -file sim_out_timing/critical_path.rpt
report_utilization    -file sim_out_timing/utilization.rpt

#use 
#vivado -mode batch -source scripts\timing.tcl -log sim_out_timing\vivado.log -journal sim_out_timing\vivado.jou 
#to run this script