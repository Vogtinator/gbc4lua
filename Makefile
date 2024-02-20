all: cpu_gen.lua

single.lua: mem.lua cpu_pre.lua cpu_gen.lua cpu_post.lua
	cat $^ > $@

cpu_gen.lua: gen_cpu.py
	./gen_cpu.py > cpu_gen.lua
