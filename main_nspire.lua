-- Convert the string in rom to a table
local rom_tbl = {}
for i = 1, #rom, 1 do
	rom_tbl[i] = rom:byte(i)
end

local bootrom = nil

local bitops = bitops_init()
local ppu = ppu_init()
local mem = mem_init(bootrom, rom_tbl, ppu)
local cpu = cpu_init(bitops, mem)

local width, height = 160, 144
local fb = {}
for idx = 1, width * height do
	fb[idx] = 0
end

local palette = {64, 128, 200, 255}

function on.paint(gc)
	local idx = 1
	for y = 1, height do
		for x = 1, width do
			gc:setColorRGB(0, palette[1+fb[idx]], 0)
			gc:fillRect(x, y, 1, 1)
			idx = idx + 1
		end
	end
end

function on.timer()
	for y = 0, 143 do
		cpu["run_dbg"](114)
		ppu.next_line()
	end

	ppu.draw_tilemap(mem.vram, fb)
	platform.window:invalidate(0, 0, width, height)

	for y = 144, 155 do
		cpu["run_dbg"](114)
		ppu.next_line()
	end
end

timer.start(0.02)
