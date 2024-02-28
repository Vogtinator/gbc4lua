function ppu_init(bitops)
	-- Lookup table to map 8b -> 16b with every second bit 0, for merging tile bit planes
	local tbl_expand = {}
	for i = 0, 255 do
		local expand = 0
		local shift = i
		-- Go from MSB to LSB
		for bit = 1, 8 do
			expand = expand * 4
			if shift >= 0x80 then
				expand = expand + 1
				shift = shift - 0x80
			end
			shift = shift * 2
		end

		tbl_expand[1+i] = expand
	end

	assert(tbl_expand[1+0x00] == 0x0000)
	assert(tbl_expand[1+0x0F] == 0x0055)
	assert(tbl_expand[1+0xF0] == 0x5500)
	assert(tbl_expand[1+0xFF] == 0x5555)

	-- PPU registers
	local reg_lcdc, reg_scx, reg_scy, reg_bgp = 0, 0, 0, 0
	local reg_obp0, reg_obp1 = 0, 0

	-- PPU state
	local ly = 0

	local ret = {}

	-- Draw tile with given palette (nil = transparent)
	-- at given offset (can be out of bounds)
	function ret.draw_tile(vram, tile, fb, x, y, c0, c1, c2, c3)
		local tile_addr = 1 + tile * 0x10
		local fb_addr = 1 + x + y * 160
		for ty = y, y + 7 do
			local pxdata = tbl_expand[1+vram[tile_addr]] + 2 * tbl_expand[1+vram[tile_addr+1]]
			for tx = x, x + 7 do
				local c
				if pxdata >= 0xC000 then
					c = c3
					pxdata = pxdata - 0xC000
				elseif pxdata >= 0x8000 then
					c = c2
					pxdata = pxdata - 0x8000
				elseif pxdata >= 0x4000 then
					c = c1
					pxdata = pxdata - 0x4000
				else
					c = c0
				end

				if tx >= 0 and tx < 160 and ty >= 0 and ty <= 144 and c then
					fb[fb_addr] = c
				end
				pxdata = pxdata * 4
				fb_addr = fb_addr + 1
			end

			tile_addr = tile_addr + 2
			fb_addr = fb_addr + 160 - 8
		end
	end

	function split_palette(reg)
		local c0 = reg % 4
		reg = (reg - c0) / 4
		c1 = reg % 4
		reg = (reg - c1) / 4
		c2 = reg % 4
		reg = (reg - c2) / 4
		c3 = reg % 4
		return c0, c1, c2, c3
	end

	function ret.draw_tilemap(vram, oam, fb)
		local bgp_0, bgp_1, bgp_2, bgp_3 = split_palette(reg_bgp)

		local vram_offset = 0x1801
		if bitops.tbl_and[0x0801 + reg_lcdc] ~= 0 then
			vram_offset = 0x1C01
		end
		for y = 0, 17 do
			for x = 0, 19 do
				ret.draw_tile(vram, vram[vram_offset + x + y * 32], fb, x * 8, y * 8, bgp_0, bgp_1, bgp_2, bgp_3)
			end
		end

		local obp0_0, obp0_1, obp0_2, obp0_3 = split_palette(reg_obp0)
		local obp1_0, obp1_1, obp1_2, obp1_3 = split_palette(reg_obp1)

		for oam_offset = 1, 0xA0, 4 do
			local y, x = oam[oam_offset], oam[oam_offset+1]
			if y > 0 and y < 160 and x > 0 and x < 160 then
				local flags = oam[oam_offset+3]
				if bitops.tbl_and[0x1001 + flags] == 0 then
					ret.draw_tile(vram, oam[oam_offset+2], fb, x - 8, y - 16, nil, obp0_1, obp0_2, obp0_3)
				else
					ret.draw_tile(vram, oam[oam_offset+2], fb, x - 8, y - 16, nil, obp1_1, obp1_2, obp1_3)
				end
			end
		end
	end

	function ret.read_byte(address)
		--print(string.format("PPU read %04x", address))
		if address == 0xFF40 then
			return reg_lcdc
		elseif address == 0xFF42 then
			return reg_scy
		elseif address == 0xFF44 then
			return ly
		elseif address == 0xFF47 then
			return reg_bgp
		else
			warn(string.format("UNIMPL: PPU read %04x", address))
			return 0
		end
	end

	function ret.write_byte(address, value)
		--print(string.format("PPU write %04x %02x", address, value))
		if address == 0xFF40 then
			reg_lcdc = value
		elseif address == 0xFF42 then
			reg_scy = value
		elseif address == 0xFF47 then
			reg_bgp = value
		elseif address == 0xFF48 then
			reg_obp0 = value
		elseif address == 0xFF49 then
			reg_obp1 = value
		else
			warn(string.format("UNIMPL: PPU write %04x %02x", address, value))
		end
	end

	function ret.next_line(mem)
		if reg_lcdc < 0x80 then
			-- PPU off
			ly = 0
			return
		end

		if ly == 144 then
			-- Begin of vblank
			mem.raise_irq(1)
		end

		if ly == 153 then
			ly = 0
		else
			ly = ly + 1
		end
	end

	return ret
end
