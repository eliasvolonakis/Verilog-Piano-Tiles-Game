# Set the working dir, where all compiled Verilog goes.
vlib work

# Compile all Verilog modules in mux.v to working dir;
# could also have multiple Verilog files.
# The timescale argument defines default time unit
# (used when no unit is specified), while the second number
# defines precision (all times are rounded to this value)
vlog -timescale 1ns/1ns control.v

# Load simulation using adder as the top level simulation module.
vsim control

# Log all signals and add some signals to waveform window.
log {/*}
# add wave {/*} would add all items in top level simulation module.
add wave {/*}

force {CLOCK_50} 0 0, 1 10 -repeat 20
force {reset_n} 1
force {start} 1

run 20000ns

