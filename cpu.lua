-- Returns a table with closures
function cpu_init()
	-- Registers. Wraparound has to be handled manually.
	-- 8 bit registers have values between 0-255
	local a, b, c, h, l = 0, 0, 0, 0, 0
	-- 16 bit registers have values between 0-65535
	local sp, pc = 0, 0
	-- Flags: Either 0 or 1
	local flag_carry, flag_zero = 0, 0

	-- The CPU implementation uses a table for opcode dispatching.
	-- Registers are read and written through upvalues (variables
	-- local to the parent function, shared by all child closures).
	local opcode_map = {}

	opcode_map[0x00] = function() -- NOP (1 cycle)
		return 1
	end

	-- Handlers for CB XX opcodes
	local opcode_map_cb = {}

	opcode_map[0xCB] = function()
		-- local subobc = read_byte(pc)
		local subobc = 0
		pc = pc + 1
		return opcode_map_cb[subobc]
	end

	local run = function(cycles)
		while cycles > 0 do
			-- local obc = read_byte(pc)
			local opc = 0
			pc = pc + 1
			cycles = cycles - opcode_map[opc]()
		end
	end

	return {
		get_pc = function() return pc end,
		run = run
	}
end

local cpu = cpu_init()

cpu["run"](5)
print(cpu["get_pc"]())
