dofile("mem.lua")
cpu_code = io.open("cpu_pre.lua", "rb"):read("*a")
cpu_code = cpu_code .. io.open("cpu_gen.lua", "rb"):read("*a")
cpu_code = cpu_code .. io.open("cpu_post.lua", "rb"):read("*a")
assert(loadstring(cpu_code, "cpu.lua"))()

local width, height = 160, 144

function init_framebuffer()
	-- Reserve space
	io.write(string.rep("\n", height/2))
end

local palette_fg = {30, 37, 90, 97}
local palette_bg = {40, 47, 100, 107}

function draw_framebuffer(fb)
	-- Move cursor to the top of the area
	io.write("\027[" .. height/2 .. "F")

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

local bootrom = nil
if #arg < 1 then
	print("Usage: main_linux.lua rom.gb")
	return 1
end
local rom = load_file(arg[1])
local mem = mem_init(bootrom, rom)
local cpu = cpu_init(mem)

--init_framebuffer()

cpu["run_dbg"](102400)
print(cpu["state_str"]())

--end_framebuffer()
os.exit()

init_framebuffer()
local fb = {}
for idx = 1, width * height, 6 do
	fb[idx] = 0
	fb[idx+1] = 1
	fb[idx+2] = 2
	fb[idx+3] = 3
	fb[idx+4] = 2
	fb[idx+5] = 2
end
--while true do
for a = 0, 10, 1 do
	for idx = 1, width * height, 1 do
		fb[idx] = math.random(0, 3)
	end
	draw_framebuffer(fb)
end
end_framebuffer()
