-- Lua 5.1 does not support bitwise operations like and, or, xor and not natively.
-- Doing it numerically for every operation would be too expensive, so use lookup tables.
-- This function generates lookup tables for 8bit + 8bit -> 8bit and, or and xor operations.
function bitops_init()
	-- Hardcoded lookup tables for 2b+2b -> 2b to seed the full 8b+8b -> 8b ones
	-- python3 -c 'print(", ".join([hex(a & b) for a in range(0,4) for b in range(0,4)]))'
	local tbl_2b_and = {0x0, 0x0, 0x0, 0x0, 0x0, 0x1, 0x0, 0x1, 0x0, 0x0, 0x2, 0x2, 0x0, 0x1, 0x2, 0x3}
	-- python3 -c 'print(", ".join([hex(a | b) for a in range(0,4) for b in range(0,4)]))'
	local tbl_2b_or = {0x0, 0x1, 0x2, 0x3, 0x1, 0x1, 0x3, 0x3, 0x2, 0x3, 0x2, 0x3, 0x3, 0x3, 0x3, 0x3}
	-- python3 -c 'print(", ".join([hex(a ^ b) for a in range(0,4) for b in range(0,4)]))'
	local tbl_2b_xor = {0x0, 0x1, 0x2, 0x3, 0x1, 0x0, 0x3, 0x2, 0x2, 0x3, 0x0, 0x1, 0x3, 0x2, 0x1, 0x0}

	-- Should the tables start at 1, which always needs a +1 for indexing
	-- or need a hash lookup for accessing 0? For now it's the former.
	local ret = {tbl_and = {}, tbl_or = {}, tbl_xor = {}}

	for a = 0, 255 do
		-- Split operands into 2b pieces
		local a0, a1, a2, a3 = a % 4, math.floor(a / 4) % 4, math.floor(a / 16) % 4, math.floor(a / 64) % 4
		-- Bitops are commutative, so a op b = r -> b op a = r.
		-- This allows
		for b = 0, a do
			local b0, b1, b2, b3 = b % 4, math.floor(b / 4) % 4, math.floor(b / 16) % 4, math.floor(b / 64) % 4

			local r_and = tbl_2b_and[1 + 4 * a0 + b0] + 4 * tbl_2b_and[1 + 4 * a1 + b1] + 16 * tbl_2b_and[1 + 4 * a2 + b2] + 64 * tbl_2b_and[1 + 4 * a3 + b3]
			ret.tbl_and[1 + 0x100 * a + b] = r_and
			ret.tbl_and[1 + 0x100 * b + a] = r_and

			local r_or = tbl_2b_or[1 + 4 * a0 + b0] + 4 * tbl_2b_or[1 + 4 * a1 + b1] + 16 * tbl_2b_or[1 + 4 * a2 + b2] + 64 * tbl_2b_or[1 + 4 * a3 + b3]
			ret.tbl_or[1 + 0x100 * a + b] = r_or
			ret.tbl_or[1 + 0x100 * b + a] = r_or

			local r_xor = tbl_2b_xor[1 + 4 * a0 + b0] + 4 * tbl_2b_xor[1 + 4 * a1 + b1] + 16 * tbl_2b_xor[1 + 4 * a2 + b2] + 64 * tbl_2b_xor[1 + 4 * a3 + b3]
			ret.tbl_xor[1 + 0x100 * a + b] = r_xor
			ret.tbl_xor[1 + 0x100 * b + a] = r_xor
		end
	end
	
	-- Self tests (and examples)
	function op(tbl, a, b) return tbl[1 + a * 0x100 + b] end

	assert(op(ret.tbl_and, 0xFF, 0x00) == 0x00)
	assert(op(ret.tbl_and, 0x00, 0xFF) == 0x00)
	assert(op(ret.tbl_and, 0xFF, 0xFF) == 0xFF)
	assert(op(ret.tbl_and, 0x12, 0xEF) == 0x02)
	assert(op(ret.tbl_and, 0xA5, 0x00) == 0x00)
	assert(op(ret.tbl_and, 0x00, 0x5A) == 0x00)
	assert(op(ret.tbl_and, 0xA5, 0x5A) == 0x00)

	assert(op(ret.tbl_or, 0xFF, 0x00) == 0xFF)
	assert(op(ret.tbl_or, 0x00, 0xFF) == 0xFF)
	assert(op(ret.tbl_or, 0xFF, 0xFF) == 0xFF)
	assert(op(ret.tbl_or, 0x12, 0xEF) == 0xFF)
	assert(op(ret.tbl_or, 0xA5, 0x00) == 0xA5)
	assert(op(ret.tbl_or, 0x00, 0x5A) == 0x5A)
	assert(op(ret.tbl_or, 0xA5, 0x5A) == 0xFF)

	assert(op(ret.tbl_xor, 0xFF, 0x00) == 0xFF)
	assert(op(ret.tbl_xor, 0x00, 0xFF) == 0xFF)
	assert(op(ret.tbl_xor, 0xFF, 0xFF) == 0x00)
	assert(op(ret.tbl_xor, 0x12, 0xEF) == 0xFD)
	assert(op(ret.tbl_xor, 0xA5, 0x00) == 0xA5)
	assert(op(ret.tbl_xor, 0x00, 0x5A) == 0x5A)
	assert(op(ret.tbl_xor, 0xA5, 0x5A) == 0xFF)

	return ret
end
