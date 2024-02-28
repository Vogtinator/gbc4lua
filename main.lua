function warn(msg)
	--print(msg)
end

dofile("mem.lua")
cpu_code = io.open("cpu_pre.lua", "rb"):read("*a")
cpu_code = cpu_code .. io.open("cpu_gen.lua", "rb"):read("*a")
cpu_code = cpu_code .. io.open("cpu_post.lua", "rb"):read("*a")
assert(loadstring(cpu_code, "cpu.lua"))()
dofile("bitops.lua")
dofile("ppu.lua")

local width, height = 160, 144

-- Load byte of file into a table
function load_file(filename)
	local f = io.open(filename, "rb")
	local s = f:read("*a")
	f:close()
	local ret = {}
	for i = 1, #s, 1 do
		ret[i] = s:byte(i)
	end
	return ret
end

local bitops, ppu, mem, cpu

local fb = {}

function love.load(args)
	love.window.setTitle("gbc4lua")
	love.window.setMode(width*2, height*2)

	rom = load_file(args[1])

	bitops = bitops_init()
	ppu = ppu_init(bitops)
	mem = mem_init(bootrom, rom, ppu, bitops)
	cpu = cpu_init(bitops, mem)

	for idx = 1, width * height do
		fb[idx] = 0
	end
end

local imgdata = love.image.newImageData(width*2, height*2)
local img = love.graphics.newImage(imgdata)

function love.draw()
	love.graphics.draw(img, 0, 0)
end

local palette = {1, 0.8, 0.4, 0.1}

function love.update(dt)
	for y = 0, 143 do
		cpu["run_dbg"](114)
		ppu.next_line(mem)
	end

	ppu.draw_tilemap(mem.vram, mem.oam, fb)

	local idx = 1
	for y = 0, height*2-1, 2 do
		for x = 0, width*2-1, 2 do
			imgdata:setPixel(x, y, 0, palette[1+fb[idx]], 0)
			imgdata:setPixel(x+1, y, 0, palette[1+fb[idx]], 0)
			imgdata:setPixel(x, y+1, 0, palette[1+fb[idx]], 0)
			imgdata:setPixel(x+1, y+1, 0, palette[1+fb[idx]], 0)
			idx = idx + 1
		end
	end
	img:replacePixels(imgdata)

	for y = 144, 155 do
		cpu["run_dbg"](114)
		ppu.next_line(mem)
	end
end
