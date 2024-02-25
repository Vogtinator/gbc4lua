all: cpu_gen.lua

gbc4lua.tns: single.lua
	luna $^ $@

single.lua: mem.lua cpu_pre.lua cpu_gen.lua cpu_post.lua bitops.lua ppu.lua rom.lua main_nspire.lua
	cat $^ > $@

cpu_gen.lua: gen_cpu.py
	./gen_cpu.py > cpu_gen.lua
