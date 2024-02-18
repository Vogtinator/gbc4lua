-- Returns a table with closures
function cpu_init(mem)
	-- Registers. Wraparound has to be handled manually.
	-- 8 bit registers have values between 0-255
	local a, b, c, d, e, h, l = 0, 0, 0, 0, 0, 0, 0
	-- 16 bit registers have values between 0-65535
	local sp, pc = 0, 0
	-- Flags: Either 0 or 1
	local flag_zero, flag_carry = 0, 0
	-- BCD flags not implemented (yet)
	-- local flag_negative, flag_half = 0, 0

	-- Local accessors for external variables
	local read_byte, read_word = mem["read_byte"], mem["read_word"]
	local write_byte, write_word = mem["write_byte"], mem["write_word"]

	-- The CPU implementation uses a table for opcode dispatching.
	-- Registers are read and written through upvalues (variables
	-- local to the parent function, shared by all child closures).
	local opcode_map = {}

	opcode_map[0x00] = function(pc, cycles) -- NOP (1 cycle)
		return pc + 1, cycles - 1
	end

	opcode_map[0x21] = function(pc, cycles) -- ld hl, imm16 (3 cycles)
		l, h = read_byte(pc + 1), read_byte(pc + 2)
		return pc + 3, cycles - 3
	end

	opcode_map[0x31] = function(pc, cycles) -- ld sp, imm16 (3 cycles)
		sp = read_word(pc + 1)
		return pc + 3, cycles - 3
	end

	opcode_map[0x3F] = function(pc, cycles) -- ccf (1 cycle)
		flag_carry = 1 - flag_carry
		return pc + 1, cycles - 1
	end

	opcode_map[0xAF] = function(pc, cycles) -- xor a, a (1 cycle)
		a = 0
		flag_zero, flag_carry = 1, 0
		return pc + 1, cycles - 1
	end

	-- Idea: Jit code generation through strings. Can be done for
	-- all basic blocks in ROM at least.
	--opcode_map[0x12] = loadstring("return function() print(pc) end")()
	--print(loadstring("function() end"))
	--opcode_map[0x12]()

	-- Handlers for CB XX opcodes
	local opcode_map_cb = {}

	opcode_map[0xCB] = function(pc, cycles)
		local subobc = read_byte(pc)
		return opcode_map_cb[subobc](pc, cycles)
	end

	local run = function(cycles)
		local pc_l = pc
		while cycles > 0 do
			local opc = read_byte(pc_l)
			pc_l, cycles = opcode_map[opc](pc_l, cycles)
		end
		pc = pc_l
		return cycles
	end

	local run_dbg = function(cycles)
		local pc_l = pc
		while cycles > 0 do
			local opc = read_byte(pc_l)
			local opc_impl = opcode_map[opc]
			if opc_impl == nil then
				print("UNIMPL: opcode " .. opc)
			end
			pc_l, cycles = opc_impl(pc_l, cycles)
		end
		pc = pc_l
		return cycles
	end

	local state_str = function()
		return string.format([[
A: %02x B: %02x C: %02x D: %02x
H: %02x L: %02x (HL: %02x%02x)
PC: %04x SP: %04x
Flags (ZC): %d%d]],
		a, b, c, d,
		h, l, h, l,
		pc, sp,
		flag_zero, flag_carry)
	end

	return {
		get_pc = function() return pc end,
		run = run,
		run_dbg = run_dbg,
		state_str = state_str,
	}
end
