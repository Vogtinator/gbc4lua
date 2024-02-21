#!/usr/bin/python3
# "[hl]" handled separtely
reg8 = {0: "b", 1: "c", 2: "d", 3: "e", 4: "h", 5: "l", 7: "a"}

opcodes = {}

def opcode(opc, func):
	if opc in opcodes:
		raise RuntimeError(f"{opc} already defined")

	opcodes[opc] = func

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
		if r_l == 1 then
			{r} = 0
			flag_zero = 1
		else
			{r} = r_l - 1
			flag_zero = 0
		end

		return pc + 1, cycles - 1""")

	opcode(0b00000110 | (idx << 3), f"""ld {r}, imm8 (2 cycles)
		{r} = read_byte(pc + 1)
		return pc + 2, cycles - 2""")

	opcode(0b01000110 | (idx << 3), f"""ld {r}, [hl] (2 cycles)
		{r} = read_byte(h * 0x100 + l)
		return pc + 1, cycles - 2""")

	#opcode(0b01110000 | (idx << 0), f"""ld [hl], {r} (2 cycles)
	#	write_byte(h * 0x100 + l, {r})
	#	return pc + 1, cycles - 2""")

	for idx_src, r_src in reg8.items():
		if r == r_src: # Self-move
			opcode(0b01000000 | (idx << 3) | idx_src, f"""ld {r}, {r_src} (1 cycle)
		return pc + 1, cycles - 1""")
		else:
			opcode(0b01000000 | (idx << 3) | idx_src, f"""ld {r}, {r_src} (1 cycle)
		{r} = {r_src}
		return pc + 1, cycles - 1""")

# push r16, pop r16
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

# call absolute and jump relative conditional
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

for opc, func in opcodes.items():
	print(f"""
	opcode_map[{hex(opc)}] = function(pc, cycles) -- {func}
	end""")
