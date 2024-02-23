-- Returns a table with closures
function cpu_init(bitops, mem)
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
	local tbl_and, tbl_or, tbl_xor = bitops.tbl_and, bitops.tbl_or, bitops.tbl_xor

	-- The CPU implementation uses a table for opcode dispatching.
	-- Registers are read and written through upvalues (variables
	-- local to the parent function, shared by all child closures).
	local opcode_map = {}

	opcode_map[0x00] = function(pc, cycles) -- NOP (1 cycle)
		return pc + 1, cycles - 1
	end

	opcode_map[0x11] = function(pc, cycles) -- ld de, imm16 (3 cycles)
		e, d = read_byte(pc + 1), read_byte(pc + 2)
		return pc + 3, cycles - 3
	end

	opcode_map[0x12] = function(pc, cycles) -- ld [de], a (2 cycles)
		write_byte(d * 0x100 + e, a)
		return pc + 1, cycles - 2
	end

	opcode_map[0x18] = function(pc, cycles) -- jr imm8 (3 cycles)
		local off = read_byte(pc + 1)
		if off > 128 then
			return pc - 254 + off, cycles - 3
		else
			return pc + off + 2, cycles - 3
		end
	end

	opcode_map[0x1F] = function(pc, cycles) -- rra (1 cycle)
		local r_l = a
		if r_l % 2 == 0 then
			a = r_l / 2 + 0x80*flag_carry
			flag_carry = 0
		else
			a = (r_l - 1) / 2 + 0x80*flag_carry
			flag_carry = 1
		end
		flag_zero = 0 -- always zero for some reason
		return pc + 1, cycles - 1
	end

	opcode_map[0x21] = function(pc, cycles) -- ld hl, imm16 (3 cycles)
		l, h = read_byte(pc + 1), read_byte(pc + 2)
		return pc + 3, cycles - 3
	end

	opcode_map[0x22] = function(pc, cycles) -- ld [hl+], a (2 cycles)
		write_byte(h * 0x100 + l, a)
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

	opcode_map[0x32] = function(pc, cycles) -- ld a, [hl-] (2 cycles)
		write_byte(h * 0x100 + l, a)
		if l > 0 then
			l = l - 1
		elseif h > 0 then
			l = 0xFF
			h = h - 1
		else
			l = 0xFF
			h = 0xFF
		end
		return pc + 1, cycles - 2
	end

	opcode_map[0x35] = function(pc, cycles) -- dec [hl] (3 cycles)
		local addr = h * 0x100 + l
		local value = read_byte(addr)
		if value > 1 then
			flag_zero = 0
			write_byte(addr, value - 1)
		elseif value == 1 then
			flag_zero = 1
			write_byte(addr, 0)
		else
			flag_zero = 0
			write_byte(addr, 0xFF)
		end
		return pc + 1, cycles - 3
	end

	opcode_map[0x3F] = function(pc, cycles) -- ccf (1 cycle)
		flag_carry = 1 - flag_carry
		return pc + 1, cycles - 1
	end

	opcode_map[0xAE] = function(pc, cycles) -- xor a, [hl] (2 cycles)
		a = tbl_xor[1 + 0x100*a + read_byte(h*0x100 + l)]
		if a == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		flag_carry = 0
		return pc + 1, cycles - 2
	end

	opcode_map[0xAF] = function(pc, cycles) -- xor a, a (1 cycle)
		a = 0
		flag_zero, flag_carry = 1, 0
		return pc + 1, cycles - 1
	end

	opcode_map[0xB6] = function(pc, cycles) -- or a, [hl] (2 cycles)
		a = tbl_or[1 + 0x100*a + read_byte(h * 0x100 + l)]
		if a == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		flag_carry = 0
		return pc + 1, cycles - 2
	end

	opcode_map[0xB7] = function(pc, cycles) -- or a, a (1 cycle)
		flag_carry = 0
		if a > 0 then
			flag_zero = 0
		else
			flag_zero = 1
		end
		return pc + 1, cycles - 1
	end

	opcode_map[0xC3] = function(pc, cycles) -- jp imm16 (3 cycles)
		return read_word(pc + 1), cycles - 3
	end

	opcode_map[0xC6] = function(pc, cycles) -- add a, imm8 (2 cycles)
		local a_l = a + read_byte(pc + 1)
		if a_l == 0 then
			flag_zero = 1
			flag_carry = 0
		elseif a_l >= 0x100 then
			flag_zero = 0
			flag_carry = 1
			a_l = a_l - 0x100
		else
			flag_zero = 0
			flag_carry = 0
		end
		a = a_l
		return pc + 2, cycles - 2
	end

	opcode_map[0xC9] = function(pc, cycles) -- ret (4 cycles)
		local sp_l = sp
		local tgt = read_word(sp_l)
		if sp_l < 0xFFFE then
			sp = sp_l + 2
		else
			sp = sp_l - 0xFFFE
		end

		return tgt, cycles - 4
	end

	opcode_map[0xCD] = function(pc, cycles) -- call imm16 (6 cycles)
		local tgt = read_word(pc + 1)
		sp = sp - 2
		if sp < 0 then
			sp = sp + 0x10000
		end

		write_word(sp, pc + 3)

		return tgt, cycles - 6
	end

	opcode_map[0xCE] = function(pc, cycles) -- adc a, imm8 (2 cycles)
		local a_l = a + read_byte(pc + 1) + flag_carry
		if a_l == 0 then
			flag_zero = 1
			flag_carry = 0
		elseif a_l >= 0x100 then
			flag_zero = 0
			flag_carry = 1
			a_l = a_l - 0x100
		else
			flag_zero = 0
			flag_carry = 0
		end
		a = a_l
		return pc + 2, cycles - 2
	end

	opcode_map[0xD6] = function(pc, cycles) -- sub a, imm8 (2 cycles)
		local a_l = a - read_byte(pc + 1)
		if a_l == 0 then
			flag_zero = 1
			flag_carry = 0
		elseif a_l < 0 then
			flag_zero = 0
			flag_carry = 1
			a_l = a_l + 0x100
		else
			flag_zero = 0
			flag_carry = 0
		end
		a = a_l
		return pc + 2, cycles - 2
	end

	opcode_map[0xE0] = function(pc, cycles) -- ldh [imm8], a (3 cycles)
		write_byte(0xFF00 + read_byte(pc + 1), a)
		return pc + 2, cycles - 3
	end

	opcode_map[0xE6] = function(pc, cycles) -- and a, imm8 (2 cycles)
		a = tbl_and[1 + 0x100*a + read_byte(pc + 1)]
		if a == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		flag_carry = 0
		return pc + 2, cycles - 2
	end

	opcode_map[0xEA] = function(pc, cycles) -- ld [imm16], a (4 cycles)
		write_byte(read_word(pc + 1), a)
		return pc + 3, cycles - 4
	end

	opcode_map[0xEE] = function(pc, cycles) -- xor a, imm8 (2 cycles)
		a = tbl_xor[1 + 0x100*a + read_byte(pc + 1)]
		if a == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		flag_carry = 0
		return pc + 2, cycles - 2
	end

	opcode_map[0xF0] = function(pc, cycles) -- ldh a, [imm8] (3 cycles)
		a = read_byte(0xFF00 + read_byte(pc + 1))
		return pc + 2, cycles - 3
	end

	opcode_map[0xF1] = function(pc, cycles) -- pop af (3 cycles)
		local sp_l = sp
		local flags = read_byte(sp_l)
		a = read_byte(sp_l + 1)

		if flags >= 0x80 then
			flag_zero = 1
		else
			flag_zero = 0
		end

		if tbl_and[0x8001 + flags] ~= 0 then
			flag_carry = 1
		else
			flag_carry = 0
		end

		sp = sp_l + 2

		return pc + 1, cycles - 3
	end

	opcode_map[0xF3] = function(pc, cycles) -- di (1 cycle)
		print("UNIMPL: DI")
		return pc + 1, cycles - 1
	end

	opcode_map[0xF5] = function(pc, cycles) -- push af (4 cycles)
		local sp_l = sp
		sp_l = sp_l - 2
		write_byte(sp_l, (flag_zero * 0x80) + (flag_carry * 0x10))
		write_byte(sp_l + 1, a)
		sp = sp_l
		return pc + 1, cycles - 4
	end

	opcode_map[0xFA] = function(pc, cycles) -- ld a, [imm16] (4 cycles)
		a = read_byte(read_word(pc + 1))
		return pc + 3, cycles - 4
	end

	opcode_map[0xFE] = function(pc, cycles) -- cp a, imm8 (2 cycles)
		local imm = read_byte(pc + 1)
		if a == imm then
			flag_zero = 1
			flag_carry = 0
		elseif a < imm then
			flag_zero = 0
			flag_carry = 1
		else
			flag_zero = 0
			flag_carry = 0
		end
		return pc + 2, cycles - 2
	end

	-- Idea: Jit code generation through strings. Can be done for
	-- all basic blocks in ROM at least.
	--opcode_map[0x12] = loadstring("return function() print(pc) end")()
	--print(loadstring("function() end"))
	--opcode_map[0x12]()

	-- Handlers for CB XX opcodes
	local opcode_map_cb = {}

	opcode_map[0xCB] = function(pc, cycles)
		local subobc = read_byte(pc + 1)
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
			-- For tracing:
			--print(string.format("PC %04x A %02x BC %02x%02x DE %02x%02x HL %02x%02x SP %04x CZ %d%d OPC %02x %02x %02x",
			--pc_l, a, b, c, d, e, h, l, sp, flag_carry, flag_zero, opc, read_byte(pc_l + 1), read_byte(pc_l + 2)))
			if opc_impl == nil then
				pc = pc_l; print(cpu.state_str());
				print(string.format("Opc: 0x%02x (%02x %02x)", opc, read_byte(pc_l + 1), read_byte(pc_l + 2)))
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
		flag_zero = 1
		c = 0x13
		e = 0xD8
		h = 0x01
		l = 0x4D
		sp = 0xFFFE
		pc = 0x0100
	end

	-- Code generated by gen_cpu.py follows here
