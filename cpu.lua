-- Returns a table with closures
function cpu_init(mem)
	local cpu = {}

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
	local read_byte, read_word = mem.read_byte, mem.read_word
	local write_byte, write_word = mem.write_byte, mem.write_word

	-- The CPU implementation uses a table for opcode dispatching.
	-- Registers are read and written through upvalues (variables
	-- local to the parent function, shared by all child closures).
	local opcode_map = {}

	opcode_map[0x00] = function(pc, cycles) -- NOP (1 cycle)
		return pc + 1, cycles - 1
	end

	opcode_map[0x0D] = function(pc, cycles) -- dec c (1 cycle)
		local c_l = c -- local for faster access
		if c_l == 1 then
			c = 0
			flag_zero = 1
		else
			c = c_l - 1
			flag_zero = 0
		end

		return pc + 1, cycles - 1
	end

	opcode_map[0x0E] = function(pc, cycles) -- LD C (2 cycles)
		c = read_byte(pc + 1)
		return pc + 2, cycles - 2
	end

	opcode_map[0x11] = function(pc, cycles) -- ld de, imm16 (3 cycles)
		e, d = read_byte(pc + 1), read_byte(pc + 2)
		return pc + 3, cycles - 3
	end

	opcode_map[0x12] = function(pc, cycles) -- ld [de], a (2 cycles)
		write_byte(d * 0x100 + e, a)
		return pc + 1, cycles - 2
	end

	opcode_map[0x14] = function(pc, cycles) -- inc d (1 cycle)
		local d_l = d -- local for faster access
		if d_l == 0xFF then
			d = 0
			flag_zero = 1
		else
			d = d_l + 1
			flag_zero = 0
		end

		return pc + 1, cycles - 1
	end

	opcode_map[0x1C] = function(pc, cycles) -- inc e (1 cycle)
		local e_l = e -- local for faster access
		if e_l == 0xFF then
			e = 0
			flag_zero = 1
		else
			e = e_l + 1
			flag_zero = 0
		end

		return pc + 1, cycles - 1
	end

	opcode_map[0x20] = function(pc, cycles) -- jr nz, imm8 (2/3 cycles)
		local pc_l = pc
		if flag_zero == 0 then
			local off = read_byte(pc_l + 1)
			if off > 128 then
				return pc_l - 254 + off, cycles - 3
			else
				return pc_l + off + 2, cycles - 3
			end
		else
			return pc + 2, cycles - 2
		end
	end

	opcode_map[0x28] = function(pc, cycles) -- jr z, imm8 (2/3 cycles)
		local pc_l = pc
		if flag_zero == 1 then
			local off = read_byte(pc_l + 1)
			if off > 128 then
				return pc_l - 254 + off, cycles - 3
			else
				return pc_l + off + 2, cycles - 3
			end
		else
			return pc + 2, cycles - 2
		end
	end

	opcode_map[0x21] = function(pc, cycles) -- ld hl, imm16 (3 cycles)
		l, h = read_byte(pc + 1), read_byte(pc + 2)
		return pc + 3, cycles - 3
	end

	opcode_map[0x2A] = function(pc, cycles) -- ld a, [hl+] (2 cycles)
		a = read_byte(h * 0x100 + l)
		if l < 0xFF then
			l = l + 1
		elseif h < 0xFF then
			l = 0
			h = h + 1
		else
			l = 0
			h = 0
		end

		return pc + 1, cycles - 2
	end

	opcode_map[0x31] = function(pc, cycles) -- ld sp, imm16 (3 cycles)
		sp = read_word(pc + 1)
		return pc + 3, cycles - 3
	end

	opcode_map[0x3F] = function(pc, cycles) -- ccf (1 cycle)
		flag_carry = 1 - flag_carry
		return pc + 1, cycles - 1
	end

	opcode_map[0x47] = function(pc, cycles) -- ld b, a (1 cycle)
		b = a
		return pc + 1, cycles - 1
	end

	opcode_map[0x78] = function(pc, cycles) -- ld a, b (1 cycle)
		a = b
		return pc + 1, cycles - 1
	end

	opcode_map[0xAF] = function(pc, cycles) -- xor a, a (1 cycle)
		a = 0
		flag_zero, flag_carry = 1, 0
		return pc + 1, cycles - 1
	end

	opcode_map[0xC3] = function(pc, cycles) -- jp imm16 (3 cycles)
		return read_word(pc + 1), cycles - 3
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

	cpu.run = function(cycles)
		local pc_l = pc
		while cycles > 0 do
			local opc = read_byte(pc_l)
			pc_l, cycles = opcode_map[opc](pc_l, cycles)
		end
		pc = pc_l
		return cycles
	end

	cpu.run_dbg = function(cycles)
		local pc_l = pc
		while cycles > 0 do
			local opc = read_byte(pc_l)
			local opc_impl = opcode_map[opc]
			if opc_impl == nil then
				pc = pc_l; print(cpu.state_str()); -- print(string.format("Opc: 0x%02x", opc))
				print(string.format("UNIMPL: opcode %02x", opc))
			end
			pc_l, cycles = opc_impl(pc_l, cycles)
		end
		pc = pc_l
		return cycles
	end

	cpu.state_str = function()
		return string.format([[
A: %02x
B: %02x C: %02x D: %02x E: %02x
H: %02x L: %02x (HL: %02x%02x)
PC: %04x SP: %04x
Flags (ZC): %d%d]],
		a,
		b, c, d, e,
		h, l, h, l,
		pc, sp,
		flag_zero, flag_carry)
	end

	cpu.get_pc = function() return pc end

	if not mem.has_bootrom() then
		a = 0x01
		-- todo: other regs
		sp = 0xfffe
		pc = 0x0100
	end

	return cpu
end
