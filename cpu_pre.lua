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
	-- BCD flags not implemented (yet) except for push/pop af + daa
	local flag_half, flag_neg = 0, 0
	-- Interrupt master enable
	local flag_ime = false

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

	opcode_map[0x07] = function(pc, cycles) -- rlca (1 cycle)
		local r_l = a
		if r_l >= 0x80 then
			a = (r_l - 0x80) * 2 + 1 -- Could be factored out
			flag_carry = 1
		else
			a = r_l * 2
			flag_carry = 0
		end
		flag_zero = 0 -- always zero for some reason
		return pc + 1, cycles - 1
	end

	opcode_map[0x0F] = function(pc, cycles) -- rrca (1 cycle)
		local r_l = a
		if r_l % 2 == 0 then
			a = r_l / 2
			flag_carry = 0
		else
			a = (r_l - 1) / 2 + 0x80
			flag_carry = 1
		end
		flag_zero = 0 -- always zero for some reason
		return pc + 1, cycles - 1
	end

	opcode_map[0x08] = function(pc, cycles) -- ld [imm16], sp (5 cycles)
		write_word(read_word(pc + 1), sp)
		return pc + 3, cycles - 5
	end

	opcode_map[0x11] = function(pc, cycles) -- ld de, imm16 (3 cycles)
		e, d = read_byte(pc + 1), read_byte(pc + 2)
		return pc + 3, cycles - 3
	end

	opcode_map[0x12] = function(pc, cycles) -- ld [de], a (2 cycles)
		write_byte(d * 0x100 + e, a)
		return pc + 1, cycles - 2
	end

	opcode_map[0x17] = function(pc, cycles) -- rla (1 cycle)
		flag_zero = 0
		if a >= 0x80 then
			a = (a - 0x80) * 2 + flag_carry
			flag_carry = 1
		else
			a = a * 2 + flag_carry
			flag_carry = 0
		end
		return pc + 1, cycles - 1
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

	-- Copied from https://blog.ollien.com/posts/gb-daa/
	opcode_map[0x27] = function(pc, cycles) -- daa (1 cycles)
		local high, low = math.floor(a / 0x10), a % 0x10
		local adj = 0

		if (flag_neg == 0 and low > 9) or flag_half == 1 then
			adj = 0x06
		end

		if (flag_neg == 0 and a > 0x99) or flag_carry == 1 then
			adj = adj + 0x60;
			flag_carry = 1
		else
			flag_carry = 0
		end

		if flag_neg == 1 then
			adj = 0x100 - adj
		end

		a = a + adj

		if a >= 0x100 then
			a = a - 0x100
		end

		if a == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end

		flag_half = 0

		return pc + 1, cycles - 1
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

	opcode_map[0x2F] = function(pc, cycles) -- cpl (1 cycle)
		a = tbl_xor[0xFF01 + a]
		return pc + 1, cycles - 1
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

	opcode_map[0x33] = function(pc, cycles) -- inc sp (2 cycles)
		if sp ~= 0xFFFF then
			sp = sp + 1
		else
			sp = 0
		end
		return pc + 1, cycles - 2
	end

	opcode_map[0x34] = function(pc, cycles) -- inc [hl] (3 cycles)
		local addr = h * 0x100 + l
		local value = read_byte(addr)
		if value == 0xFF then
			write_byte(addr, 0)
			flag_zero = 1
		else
			write_byte(addr, value + 1)
			flag_zero = 0
		end
		return pc + 1, cycles - 3
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

	opcode_map[0x36] = function(pc, cycles) -- ld [hl], imm8 (3 cycles)
		write_byte(h * 0x100 + l, read_byte(pc + 1))
		return pc + 2, cycles - 3
	end

	opcode_map[0x37] = function(pc, cycles) -- scf (1 cycle)
		flag_carry = 1
		return pc + 1, cycles - 1
	end

	opcode_map[0x39] = function(pc, cycles) -- add hl, sp (2 cycles)
		local hl = h*0x100 + l
		hl = hl + sp

		if hl >= 0x10000 then
			hl = hl - 0x10000
			flag_carry = 1
		else
			flag_carry = 0
		end

		h = math.floor(hl / 0x100)
		l = hl % 0x100

		return pc + 1, cycles - 2
	end

	opcode_map[0x3A] = function(pc, cycles) -- ld [hl-], a (2 cycles)
		a = read_byte(h * 0x100 + l)
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

	opcode_map[0x3B] = function(pc, cycles) -- dec sp (2 cycles)
		if sp == 0 then
			sp = 0xFFFF
		else
			sp = sp - 1
		end
		return pc + 1, cycles - 2
	end

	opcode_map[0x3F] = function(pc, cycles) -- ccf (1 cycle)
		flag_carry = 1 - flag_carry
		return pc + 1, cycles - 1
	end

	opcode_map[0x76] = function(pc, cycles) -- halt
		-- Return to main loop.
		-- TODO: Keep in halted state until an interrupt actually occurs
		-- to avoid spurious wakeups.
		return pc + 1, 0
	end

	opcode_map[0x86] = function(pc, cycles) -- add a, [hl] (2 cycles)
		local r_l = a + read_byte(0x100*h + l)
		if r_l == 0 then
			flag_zero = 1
			flag_carry = 0
			a = r_l
		elseif r_l == 0x100 then
			flag_zero = 1
			flag_carry = 1
			a = r_l - 0x100
		elseif r_l > 0x100 then
			flag_zero = 0
			flag_carry = 1
			a = r_l - 0x100
		else
			flag_zero = 0
			flag_carry = 0
			a = r_l
		end
		return pc + 1, cycles - 2
	end

	opcode_map[0x8E] = function(pc, cycles) -- adc a, [hl] (2 cycles)
		local r_l = a + read_byte(0x100*h + l) + flag_carry
		if r_l == 0 then
			flag_zero = 1
			flag_carry = 0
			a = r_l
		elseif r_l == 0x100 then
			flag_zero = 1
			flag_carry = 1
			a = r_l - 0x100
		elseif r_l > 0x100 then
			flag_zero = 0
			flag_carry = 1
			a = r_l - 0x100
		else
			flag_zero = 0
			flag_carry = 0
			a = r_l
		end
		return pc + 1, cycles - 2
	end

	opcode_map[0x96] = function(pc, cycles) -- sub a, [hl] (2 cycles)
		local r_l = a - read_byte(0x100*h + l)
		if r_l == 0 then
			flag_zero = 1
			flag_carry = 0
			a = r_l
		elseif r_l < 0 then
			flag_zero = 0
			flag_carry = 1
			a = r_l + 0x100
		else
			flag_zero = 0
			flag_carry = 0
			a = r_l
		end
		return pc + 1, cycles - 2
	end

	opcode_map[0x9E] = function(pc, cycles) -- sbc a, [hl] (2 cycles)
		local r_l = a - read_byte(0x100*h + l) - flag_carry
		if r_l == 0 then
			flag_zero = 1
			flag_carry = 0
			a = r_l
		elseif r_l < 0 then
			flag_zero = 0
			flag_carry = 1
			a = r_l + 0x100
		else
			flag_zero = 0
			flag_carry = 0
			a = r_l
		end
		return pc + 1, cycles - 2
	end

	opcode_map[0xA6] = function(pc, cycles) -- and a, [hl] (2 cycles)
		local r_l = tbl_and[1 + 0x100 * a + read_byte(0x100*h + l)]
		a = r_l
		flag_carry = 0
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		return pc + 1, cycles - 2
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

	opcode_map[0xBE] = function(pc, cycles) -- cp a, [hl] (2 cycles)
		local r_l = read_byte(h*0x100 + l)
		if a == r_l then
			flag_zero = 1
			flag_carry = 0
		elseif a < r_l then
			flag_zero = 0
			flag_carry = 1
		else
			flag_zero = 0
			flag_carry = 0
		end
		return pc + 1, cycles - 2
	end

	opcode_map[0xBF] = function(pc, cycles) -- cp a, a (1 cycle)
		flag_zero, flag_carry = 1, 0
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
		elseif a_l == 0x100 then
			flag_zero = 1
			flag_carry = 1
			a_l = a_l - 0x100
		elseif a_l > 0x100 then
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
		sp = sp_l + 2
		return tgt, cycles - 4
	end

	opcode_map[0xCD] = function(pc, cycles) -- call imm16 (6 cycles)
		local tgt = read_word(pc + 1)
		sp = sp - 2
		write_word(sp, pc + 3)
		return tgt, cycles - 6
	end

	opcode_map[0xCE] = function(pc, cycles) -- adc a, imm8 (2 cycles)
		local a_l = a + read_byte(pc + 1) + flag_carry
		if a_l == 0 then
			flag_zero = 1
			flag_carry = 0
		elseif a_l == 0x100 then
			flag_zero = 1
			flag_carry = 1
			a_l = a_l - 0x100
		elseif a_l > 0x100 then
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

	opcode_map[0xD9] = function(pc, cycles) -- reti (4 cycles)
		local sp_l = sp
		local tgt = read_word(sp_l)
		sp = sp_l + 2
		flag_ime = true
		return tgt, cycles - 4
	end

	opcode_map[0xDE] = function(pc, cycles) -- sbc a, imm8 (2 cycles)
		local a_l = a - read_byte(pc + 1) - flag_carry
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

	opcode_map[0xE2] = function(pc, cycles) -- ldh [c], a (2 cycles)
		write_byte(0xFF00 + c, a)
		return pc + 1, cycles - 2
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

	opcode_map[0xE8] = function(pc, cycles) -- add sp, imm8 (4 cycles)
		local imm = read_byte(pc + 1) -- signed
		if imm < 128 then
			sp = sp + imm
		else
			sp = sp - 256 + imm
		end
		flag_zero = 0
		if sp >= 0x10000 then
			flag_carry = 1
			sp = sp - 0x10000
		else
			flag_carry = 0
		end
		return pc + 2, cycles - 4
	end

	opcode_map[0xE9] = function(pc, cycles) -- jp hl (1 cycle)
		return h * 0x100 + l, cycles - 1
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

	opcode_map[0xF2] = function(pc, cycles) -- ld a, [c] (2 cycles)
		a = read_byte(0xFF00 + c)
		return pc + 1, cycles - 2
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

		if tbl_and[0x4001 + flags] ~= 0 then
			flag_neg = 1
		else
			flag_neg = 0
		end

		if tbl_and[0x2001 + flags] ~= 0 then
			flag_half = 1
		else
			flag_half = 0
		end

		if tbl_and[0x1001 + flags] ~= 0 then
			flag_carry = 1
		else
			flag_carry = 0
		end

		sp = sp_l + 2

		return pc + 1, cycles - 3
	end

	opcode_map[0xF3] = function(pc, cycles) -- di (1 cycle)
		flag_ime = false
		return pc + 1, cycles - 1
	end

	opcode_map[0xF5] = function(pc, cycles) -- push af (4 cycles)
		local sp_l = sp
		sp_l = sp_l - 2
		--write_byte(sp_l, (flag_zero * 0x80) + (flag_carry * 0x10))
		write_byte(sp_l, (flag_zero * 0x80) + (flag_neg * 0x40) + (flag_half * 0x20) + (flag_carry * 0x10))
		write_byte(sp_l + 1, a)
		sp = sp_l
		return pc + 1, cycles - 4
	end

	opcode_map[0xF6] = function(pc, cycles) -- or a, imm8 (2 cycles)
		a = tbl_or[1 + 0x100*a + read_byte(pc + 1)]
		if a == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		flag_carry = 0
		return pc + 2, cycles - 2
	end

	opcode_map[0xF8] = function(pc, cycles) -- ld hl, sp + imm8 (3 cycles)
		local imm = read_byte(pc + 1) -- signed
		local hl = sp
		if imm < 128 then
			hl = hl + imm
		else
			hl = hl + 256 - imm
		end
		flag_zero = 0
		if hl >= 0x10000 then
			flag_carry = 1
			hl = hl - 0x10000
		else
			flag_carry = 0
		end

		h = math.floor(hl / 0x100)
		l = hl % 0x100

		return pc + 2, cycles - 3
	end

	opcode_map[0xF9] = function(pc, cycles) -- ld sp, hl (2 cycles)
		sp = h * 0x100 + l
		return pc + 1, cycles - 2
	end

	opcode_map[0xFA] = function(pc, cycles) -- ld a, [imm16] (4 cycles)
		a = read_byte(read_word(pc + 1))
		return pc + 3, cycles - 4
	end

	opcode_map[0xFB] = function(pc, cycles) -- ei (1 cycle)
		flag_ime = true -- On HW delayed by a cycle but hopefully doesn't matter
		return pc + 1, cycles - 1
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
		--To make some tests happy
		--flag_neg, flag_half = 0, 0
		return opcode_map_cb[subobc](pc, cycles)
	end

	opcode_map_cb[0x06] = function(pc, cycles) -- rlc [hl] (4 cycles)
		local addr = 0x100*h + l
		local r_l = read_byte(addr)
		if r_l >= 0x80 then
			r_l = (r_l - 0x80) * 2 + 1 -- Could be factored out
			flag_carry = 1
		else
			r_l = r_l * 2
			flag_carry = 0
		end
		write_byte(addr, r_l)
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		return pc + 2, cycles - 4
	end

	opcode_map_cb[0x0E] = function(pc, cycles) -- rrc [hl] (4 cycles)
		local addr = 0x100*h + l
		local r_l = read_byte(addr)
		if r_l % 2 == 0 then
			r_l = r_l / 2
			flag_carry = 0
		else
			r_l = (r_l - 1) / 2 + 0x80
			flag_carry = 1
		end
		write_byte(addr, r_l)
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		return pc + 2, cycles - 4
	end

	opcode_map_cb[0x16] = function(pc, cycles) -- rl [hl] (4 cycles)
		local addr = 0x100*h + l
		local r_l = read_byte(addr)
		if r_l >= 0x80 then
			r_l = (r_l - 0x80) * 2 + flag_carry
			flag_carry = 1
		else
			r_l = r_l * 2 + flag_carry
			flag_carry = 0
		end
		write_byte(addr, r_l)
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		return pc + 2, cycles - 4
	end

	opcode_map_cb[0x1E] = function(pc, cycles) -- rr [hl] (4 cycles)
		local addr = 0x100*h + l
		local r_l = read_byte(addr)
		if r_l % 2 == 0 then
			r_l = r_l / 2 + 0x80*flag_carry
			flag_carry = 0
		else
			r_l = (r_l - 1) / 2 + 0x80*flag_carry
			flag_carry = 1
		end
		write_byte(addr, r_l)
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		return pc + 2, cycles - 4
	end

	opcode_map_cb[0x26] = function(pc, cycles) -- sla [hl] (4 cycles)
		local addr = 0x100*h + l
		local r_l = read_byte(addr)
		if r_l >= 0x80 then
			r_l = (r_l - 0x80) * 2
			flag_carry = 1
		else
			r_l = r_l * 2
			flag_carry = 0
		end
		write_byte(addr, r_l)
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		return pc + 2, cycles - 4
	end

	opcode_map_cb[0x2E] = function(pc, cycles) -- sra [hl] (4 cycles)
		local addr = 0x100*h + l
		local r_l = read_byte(addr)
		if r_l % 2 == 1 then
			r_l = (r_l - 1) / 2
			flag_carry = 1
		else
			r_l = r_l / 2
			flag_carry = 0
		end
		if r_l >= 0x40 then
			r_l = r_l + 0x80
		end
		write_byte(addr, r_l)
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		return pc + 2, cycles - 4
	end

	opcode_map_cb[0x36] = function(pc, cycles) -- swap [hl] (4 cycles)
		local addr = 0x100*h + l
		local r_l = read_byte(addr)
		flag_carry = 0
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end

		-- Use lookup table instead?
		write_byte(addr, math.floor(r_l / 0x10) + (r_l % 0x10) * 0x10)
		return pc + 2, cycles - 4
	end

	opcode_map_cb[0x3E] = function(pc, cycles) -- srl [hl] (4 cycles)
		local addr = 0x100*h + l
		local r_l = read_byte(addr)
		if r_l == 0 then
			flag_carry = 0
			flag_zero = 1
		elseif r_l == 1 then
			flag_carry = 1
			flag_zero = 1
			write_byte(addr, 0)
		else
			flag_carry = r_l % 2
			flag_zero = 0
			write_byte(addr, math.floor(r_l / 2))
		end
		return pc + 2, cycles - 4
	end

	local function check_interrupts(pc, cycles)
		if not flag_ime then
			return pc, cycles
		end

		local irq = mem.next_irq()
		if not irq then
			return pc, cycles
		end

		flag_ime = false
		sp = sp - 2
		write_word(sp, pc)
		return 0x40 + 8*irq, cycles - 5
	end

	cpu.run = function(cycles)
		local opcode_map_l, read_byte_l = opcode_map, read_byte
		local pc_l = pc
		pc_l, cycles = check_interrupts(pc_l, cycles)
		while cycles > 0 do
			local opc = read_byte_l(pc_l)
			pc_l, cycles = opcode_map_l[opc](pc_l, cycles)
		end
		pc = pc_l
		return cycles
	end

	local function assert_1b(r)
		assert(r == 0 or r == 1)
	end

	local function assert_8b(r)
		assert(r == math.floor(r))
		assert(r >= 0 and r <= 0xFF)
	end

	local function assert_16b(r)
		assert(r == math.floor(r))
		assert(r >= 0 and r <= 0xFFFF)
	end

	local function validate()
		assert_8b(a);
		assert_8b(b); assert_8b(c);
		assert_8b(d); assert_8b(e);
		assert_8b(h); assert_8b(l);
		assert_16b(sp); assert_16b(pc);
		assert_1b(flag_carry); assert_1b(flag_zero);
	end

	cpu.run_dbg = function(cycles)
		local pc_l = pc
		while cycles > 0 do
			pc_l, cycles = check_interrupts(pc_l, cycles)
			local opc = read_byte(pc_l)
			local opc_impl = opcode_map[opc]
			-- For tracing:
			--pc = pc_l; print(cpu.state_str());
			if opc_impl == nil or opc == 0xCB and opcode_map_cb[read_byte(pc_l+1)] == nil then
				pc = pc_l; print(cpu.state_str())
				assert(false, string.format("UNIMPL: opcode %02x", opc))
			end
			pc_l, cycles = opc_impl(pc_l, cycles)
			--validate()
		end
		pc = pc_l
		return cycles
	end

	function cpu.state_str()
		return string.format("PC %02x %04x A %02x BC %02x%02x DE %02x%02x HL %02x%02x SP %04x CZ %d%d OPC %02x %02x %02x",
			mem.get_rom_bank(pc), pc, a, b, c, d, e, h, l, sp, flag_carry, flag_zero, read_byte(pc), read_byte(pc + 1), read_byte(pc + 2))
	end

	function cpu.get_pc() return pc end

	if not mem.has_bootrom() then
		a = 0x01
		flag_zero = 1
		c = 0x13
		e = 0xD8
		h = 0x01
		l = 0x4D
		sp = 0xFFFE
		pc = 0x0100

		write_byte(0xFF00, 0xCF)
		write_byte(0xFF02, 0x7E)
		write_byte(0xFF04, 0x18)
		write_byte(0xFF07, 0xF8)
		write_byte(0xFF0F, 0xE1)
		write_byte(0xFF40, 0x91)
		write_byte(0xFF41, 0x81)
		--write_byte(0xFF46, 0xFF)
		write_byte(0xFF47, 0xFC)
	end

	-- Code generated by gen_cpu.py follows here
