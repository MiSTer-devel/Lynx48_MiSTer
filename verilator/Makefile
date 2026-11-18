# Verilator simulator for the Lynx core (rtl/lynx_core.sv at the 48 MHz clk_sys rate).
# Needs Verilator 5.x and zlib.   make / make clean / ./obj_dir/Vlynx_sim --help
RTL = ../rtl
TOP = lynx_sim
EXE = obj_dir/V$(TOP)

V_SRC = lynx_sim.sv $(RTL)/lynx_core.sv $(RTL)/lynx_48k.v $(RTL)/video_48k.v \
	$(RTL)/lynx_128k.v $(RTL)/video_128k.v $(RTL)/cpu.v $(RTL)/t80sv/t80sv_all.sv \
	$(RTL)/lynx_tap.sv $(RTL)/lynx_wav.sv $(RTL)/lynx_tape_overlay.sv $(RTL)/matrix.v $(RTL)/UM6845R.v $(RTL)/wd1793.sv $(RTL)/vram.v

V_FLAGS = +incdir+$(RTL) --cc --exe --build -j 0 --top-module $(TOP) --no-timing -Wno-fatal -Wno-lint -Wno-style \
	--x-assign fast --x-initial fast --noassert -O3 \
	-CFLAGS "-O2 -std=c++17" -LDFLAGS "-lz"

all: $(EXE) boot.hex boot1.hex

# the core's $readmemh names are bare (Quartus finds them next to the source)
boot.hex boot1.hex:
	ln -sf $(RTL)/$@ $@

$(EXE): $(V_SRC) sim_main.cpp Makefile
	verilator $(V_FLAGS) $(V_SRC) sim_main.cpp

clean:
	rm -rf obj_dir boot.hex boot1.hex
