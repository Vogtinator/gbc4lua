#!/usr/bin/python3
# "[hl]" handled separtely
reg8 = {0: "b", 1: "c", 2: "d", 3: "e", 4: "h", 5: "l", 7: "a"}

reg16 = {0: "bc", 1: "de", 2: "hl", 3: "sp"}
reg16 = {0: "bc", 1: "de", 2: "hl", 3: "sp"}

opcodes = {}

def opcode(opc, func):
	if opc in opcodes:
		raise RuntimeError(f"{opc} already defined")

	opcodes[opc] = func

# inc, dec, ld r imm8, ld r8 r8
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

	for idx_src, r_src in reg8.items():
		opcode(0b01000000 | (idx << 3) | idx_src, f"""ld {r}, {r_src} (1 cycle)
		{r} = {r_src}
		return pc + 1, cycles - 1""")

# jump relative conditional
for opc, insn, cond in [(0, "nz", "flag_zero == 0"), (1, "z", "flag_zero == 1"),
                        (2, "nc", "flag_carry == 0"), (3, "c", "flag_carry == 1")]:
	opcode(0b00100000 | opc << 3, f"""jr {insn}, imm8 (2/3 cycles)
		local pc_l = pc
		if {cond} then
			local off = read_byte(pc_l + 1)
			if off > 128 then
				return pc_l - 254 + off, cycles - 3
			else
				return pc_l + off + 2, cycles - 3
			end
		else
			return pc + 2, cycles - 2
		end""")

for opc, func in opcodes.items():
	print(f"""
	opcode_map[{hex(opc)}] = function(pc, cycles) -- {func}
	end""")
