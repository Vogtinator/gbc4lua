#!/usr/bin/python3
# "[hl]" handled separtely
reg8 = {0: "b", 1: "c", 2: "d", 3: "e", 4: "h", 5: "l", 7: "a"}

opcodes = {}
def opcode(opc, func):
	if opc in opcodes:
		raise RuntimeError(f"{hex(opc)} already defined")

	opcodes[opc] = func

opcodes_cb = {}
def opcode_cb(opc, func):
	if opc in opcodes_cb:
		raise RuntimeError(f"cb {hex(opc)} already defined")

	opcodes_cb[opc] = func

# inc, dec, ld r imm8, ld r8 r8, ld r8 [hl]
for idx, r in reg8.items():
	opcode(0b00000100 | (idx << 3), f"""inc {r} (1 cycle)
		local r_l = {r} -- local for faster access
		if r_l == 0xFF then
			{r} = 0
			flag_zero = 1
		else
			{r} = r_l + 1
			flag_zero = 0
		end

		return pc + 1, cycles - 1""")

	opcode(0b00000101 | (idx << 3), f"""dec {r} (1 cycle)
		local r_l = {r} -- local for faster access
		if r_l > 1 then
			{r} = r_l - 1
			flag_zero = 0
		elseif r_l == 1 then
			{r} = 0
			flag_zero = 1
		else -- r_l == 0
			{r} = 0xFF
			flag_zero = 0
		end

		return pc + 1, cycles - 1""")

	opcode(0b00000110 | (idx << 3), f"""ld {r}, imm8 (2 cycles)
		{r} = read_byte(pc + 1)
		return pc + 2, cycles - 2""")

	opcode(0b01000110 | (idx << 3), f"""ld {r}, [hl] (2 cycles)
		{r} = read_byte(h * 0x100 + l)
		return pc + 1, cycles - 2""")

	opcode(0b01110000 | (idx << 0), f"""ld [hl], {r} (2 cycles)
		write_byte(h * 0x100 + l, {r})
		return pc + 1, cycles - 2""")

	opcode(0b10000000 | idx, f"""add a, {r} (1 cycle)
		local r_l = a + {r}
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
		return pc + 1, cycles - 1""")

	opcode(0b10001000 | idx, f"""adc a, {r} (1 cycle)
		local r_l = a + {r} + flag_carry
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
		return pc + 1, cycles - 1""")

	opcode(0b10010000 | idx, f"""sub a, {r} (1 cycle)
		local r_l = a - {r}
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
		return pc + 1, cycles - 1""")

	opcode(0b10011000 | idx, f"""sub a, {r} (1 cycle)
		local r_l = a - {r} - flag_carry
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
		return pc + 1, cycles - 1""")

	opcode(0b10100000 | idx, f"""and a, {r} (1 cycle)
		local r_l = tbl_and[1 + 0x100 * a + {r}]
		a = r_l
		flag_carry = 0
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		return pc + 1, cycles - 1""")

	opcode_cb(0b00000000 | idx, f"""rlc {r} (2 cycles)
		local r_l = {r}
		if r_l >= 0x80 then
			r_l = (r_l - 0x80) * 2 + 1 -- Could be factored out
			flag_carry = 1
		else
			r_l = r_l * 2
			flag_carry = 0
		end
		{r} = r_l
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		return pc + 2, cycles - 2""")

	opcode_cb(0b00001000 | idx, f"""rrc {r} (2 cycles)
		local r_l = {r}
		if r_l % 2 == 0 then
			r_l = r_l / 2
			flag_carry = 0
		else
			r_l = (r_l - 1) / 2 + 0x80
			flag_carry = 1
		end
		{r} = r_l
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		return pc + 2, cycles - 2""")

	opcode_cb(0b00010000 | idx, f"""rl {r} (2 cycles)
		local r_l = {r}
		if r_l >= 0x80 then
			r_l = (r_l - 0x80) * 2 + flag_carry
			flag_carry = 1
		else
			r_l = r_l * 2 + flag_carry
			flag_carry = 0
		end
		{r} = r_l
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		return pc + 2, cycles - 2""")

	opcode_cb(0b00100000 | idx, f"""sla {r} (2 cycles)
		local r_l = {r}
		if r_l >= 0x80 then
			r_l = (r_l - 0x80) * 2
			flag_carry = 1
		else
			r_l = r_l * 2
			flag_carry = 0
		end
		{r} = r_l
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		return pc + 2, cycles - 2""")

	opcode_cb(0b00101000 | idx, f"""sra {r} (2 cycles)
		local r_l = {r}
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
		{r} = r_l
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		return pc + 2, cycles - 2""")

	opcode_cb(0b00110000 | idx, f"""swap {r} (2 cycles)
		local r_l = {r}
		flag_carry = 0
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end

		-- Use lookup table instead?
		{r} = math.floor(r_l / 0x10) + (r_l % 0x10) * 0x10
		return pc + 2, cycles - 2""")

	opcode_cb(0b00111000 | idx, f"""srl {r} (2 cycles)
		local r_l = {r}
		if r_l == 0 then
			flag_carry = 0
			flag_zero = 1
		elseif r_l == 1 then
			flag_carry = 1
			flag_zero = 1
			{r} = 0
		else
			flag_carry = r_l % 2
			flag_zero = 0
			{r} = math.floor(r_l / 2)
		end
		return pc + 2, cycles - 2""")

	opcode_cb(0b00011000 | idx, f"""rr {r} (2 cycles)
		local r_l = {r}
		if r_l % 2 == 0 then
			r_l = r_l / 2 + 0x80*flag_carry
			flag_carry = 0
		else
			r_l = (r_l - 1) / 2 + 0x80*flag_carry
			flag_carry = 1
		end
		if r_l == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		{r} = r_l
		return pc + 2, cycles - 2""")

	if r != "a":
		opcode(0b10110000 | idx, f"""or a, {r} (1 cycle)
		a = tbl_or[1 + 0x100*a + {r}]
		if a == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		flag_carry = 0
		return pc + 1, cycles - 1""")

		opcode(0b10101000 | idx, f"""xor a, {r} (1 cycle)
		a = tbl_xor[1 + 0x100*a + {r}]
		if a == 0 then
			flag_zero = 1
		else
			flag_zero = 0
		end
		flag_carry = 0
		return pc + 1, cycles - 1""")

		opcode(0b10111000 | idx, f"""cp a, {r} (1 cycle)
		local r_l = {r}
		if a == {r} then
			flag_zero = 1
			flag_carry = 0
		elseif a < {r} then
			flag_zero = 0
			flag_carry = 1
		else
			flag_zero = 0
			flag_carry = 0
		end
		return pc + 1, cycles - 1""")

	for idx_src, r_src in reg8.items():
		if r == r_src: # Self-move
			opcode(0b01000000 | (idx << 3) | idx_src, f"""ld {r}, {r_src} (1 cycle)
		return pc + 1, cycles - 1""")
		else:
			opcode(0b01000000 | (idx << 3) | idx_src, f"""ld {r}, {r_src} (1 cycle)
		{r} = {r_src}
		return pc + 1, cycles - 1""")

# push r16, pop r16, ld r16 imm16, inc r16, dec r16, add hl r16
for rh, rl, opc in [("b", "c", 0), ("d", "e", 1), ("h", "l", 2)]:
	opcode(0b11000001 | opc << 4, f"""pop {rh}{rl} (3 cycles)
		local sp_l = sp
		{rl}, {rh} = read_byte(sp_l), read_byte(sp_l + 1)
		if sp_l < 0xFFFE then
			sp = sp_l + 2
		else
			sp = sp_l - 0xFFFE
		end
		return pc + 1, cycles - 3""")

	opcode(0b11000101 | opc << 4, f"""push {rh}{rl} (4 cycles)
		local sp_l = sp
		if sp_l >= 2 then
			sp_l = sp_l - 2
		else
			sp_l = sp_l + 0xFFFE
		end
		write_byte(sp_l, {rl})
		write_byte(sp_l + 1, {rh})
		sp = sp_l
		return pc + 1, cycles - 4""")

	opcode(0b00000001 | opc << 4, f"""ld {rh}{rl} (3 cycles)
		{rl}, {rh} = read_byte(pc + 1), read_byte(pc + 2)
		return pc + 3, cycles - 3""")

	opcode(0b00000011 | opc << 4, f"""inc {rh}{rl} (2 cycles)
		if {rl} < 0xFF then
			{rl} = {rl} + 1
		elseif {rh} < 0xFF then
			{rl} = 0
			{rh} = {rh} + 1
		else
			{rl} = 0
			{rh} = 0
		end
		return pc + 1, cycles - 2""")

	opcode(0b00001011 | opc << 4, f"""dec {rh}{rl} (2 cycles)
		if {rl} > 0 then
			{rl} = {rl} - 1
		elseif {rh} > 0 then
			{rl} = 0xFF
			{rh} = {rh} - 1
		else
			{rl} = 0xFF
			{rh} = 0xFF
		end
		return pc + 1, cycles - 2""")

	opcode(0b00001001 | opc << 4, f"""add hl, {rh}{rl} (2 cycles)
		-- Manual carry might be faster?
		local hl = h*0x100 + l
		hl = hl + {rh}*0x100 + {rl} -- Could be avoided for add hl, hl

		if hl >= 0x10000 then
			hl = hl - 0x10000
			flag_carry = 1
		else
			flag_carry = 0
		end

		h = math.floor(hl / 0x100)
		l = hl % 0x100

		return pc + 1, cycles - 2""")

# ld a [r16]
for rh, rl, opc in [("b", "c", 0), ("d", "e", 1)]:
	opcode(0b00001010 | opc << 4, f"""ld a, [{rh}{rl}] (2 cycles)
		a = read_byte({rh} * 0x100 + {rl})
		return pc + 1, cycles - 2""")

# ret, call absolute and jump relative conditional
for opc, insn, cond in [(0, "nz", "flag_zero == 0"), (1, "z", "flag_zero == 1"),
                        (2, "nc", "flag_carry == 0"), (3, "c", "flag_carry == 1")]:
	opcode(0b00100000 | opc << 3, f"""jr {insn}, imm8 (2/3 cycles)
		if {cond} then
			local off = read_byte(pc + 1)
			if off > 128 then
				return pc - 254 + off, cycles - 3
			else
				return pc + off + 2, cycles - 3
			end
		else
			return pc + 2, cycles - 2
		end""")

	opcode(0b11000010 | opc << 3, f"""jp {insn}, imm16 (3/4 cycles)
		if {cond} then
			return read_word(pc + 1), cycles - 4
		else
			return pc + 3, cycles - 3
		end""")

	opcode(0b11000100 | opc << 3, f"""call {insn}, imm16 (3/6 cycles)
		if {cond} then
			local tgt = read_word(pc + 1)
			sp = sp - 2
			if sp < 0 then
				sp = sp + 0x10000
			end
			write_word(sp, pc + 3)
			return tgt, cycles - 6
		else
			return pc + 3, cycles - 3
		end""")

	opcode(0b11000000 | opc << 3, f"""ret {insn} (2/4 cycles)
		if {cond} then
			local sp_l = sp
			local tgt = read_word(sp_l)
			if sp_l < 0xFFFE then
				sp = sp_l + 2
			else
				sp = sp_l - 0xFFFE
			end
			return tgt, cycles - 6
		else
			return pc + 1, cycles - 2
		end""")

for i in range(0, 8):
	opcode(0b11000111 | i << 3, f"""rst ${i} (4 cycles)
		sp = sp - 2
		if sp < 0 then
			sp = sp + 0x10000
		end
		write_word(sp, pc + 1)
		return {i*8}, cycles - 4""")

for opc, func in opcodes.items():
	print(f"""
	opcode_map[{hex(opc)}] = function(pc, cycles) -- {func}
	end""")

for opc, func in opcodes_cb.items():
	print(f"""
	opcode_map_cb[{hex(opc)}] = function(pc, cycles) -- {func}
	end""")
