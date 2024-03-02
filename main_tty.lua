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

function init_framebuffer()
	-- Reserve space
	io.write(string.rep("\n", height/2))
end

local palette_fg = {97, 90, 37, 30}
local palette_bg = {107, 100, 47, 40}

function draw_framebuffer(fb)
	-- Hide cursor and move it to the top of the area
	io.write("\027[?25l\027[" .. height/2 .. "F")

	local idx = 1
	for y = 0, height - 2, 2 do
		-- Draw two lines at once
		for offset = idx, idx + width - 1, 1 do
			io.write("\027[" .. palette_fg[1+fb[offset]] .. ";" .. palette_bg[1+fb[offset+width]] .. "m▀")
		end
		idx = idx + width * 2

		-- Move to beginning of next line
		io.write("\027[1E")
	end

	-- Reset attributes and show the cursor
	io.write("\027[0m\027[?25h")
end

function end_framebuffer()
	-- Reset attributes
	io.write("\027[0m")
end

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

local bootom, rom
if #arg == 1 then
	rom = load_file(arg[1])
elseif #arg == 2 then
	rom = load_file(arg[1])
	bootrom = load_file(arg[2])
else
	print("Usage: main_linux.lua rom.gb [bootrom.bin]")
	return 1
end
local bitops = bitops_init()
local ppu = ppu_init(bitops)
local mem = mem_init(bootrom, rom, ppu, bitops)
local cpu = cpu_init(bitops, mem)

init_framebuffer()

local fb = {}
for idx = 1, width * height do
	fb[idx] = 0
end

while true do
	for y = 1, 154 do
		cpu.run_dbg(114)
		ppu.next_line(mem, fb)
	end

	draw_framebuffer(fb)
end

end_framebuffer()
