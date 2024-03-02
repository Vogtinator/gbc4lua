function warn(msg)
	--print(msg)
end

-- Convert the string in rom to a table
local rom_tbl = {}
for i = 1, #rom, 1 do
	rom_tbl[i] = rom:byte(i)
end

local bootrom = nil

local bitops = bitops_init()
local ppu = ppu_init(bitops)
local mem = mem_init(bootrom, rom_tbl, ppu, bitops)
local cpu = cpu_init(bitops, mem)

local width, height = 160, 144
local fb = {}
for idx = 1, width * height do
	fb[idx] = 0
end

local palette = {255, 200, 128, 64}

function on.paint(gc)
	local idx = 1
	local fb_l, palette_l = fb, palette
	local gc_setColorRGB_l, gc_fillRect_l = gc.setColorRGB, gc.fillRect
	for y = 1, height do
		for x = 1, width do
			gc_setColorRGB_l(gc, 0, palette_l[1+fb_l[idx]], 0)
			gc_fillRect_l(gc, x, y, 1, 1)
			idx = idx + 1
		end
	end
end

function on.timer()
	local cpu_run = cpu.run
	local ppu_next_line = ppu.next_line
	for frame = 1, 5 do
		for y = 1, 154 do
			cpu_run(114)
			ppu_next_line(mem, fb)
		end
	end

	platform.window:invalidate(0, 0, width, height)
end

timer.start(0.05)
collectgarbage()
