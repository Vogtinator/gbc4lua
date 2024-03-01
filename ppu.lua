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
	local reg_stat = 0

	-- PPU state
	local ly, mode = 0, 1

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
		local signed_addr_mode = bitops.tbl_and[0x1001 + reg_lcdc] == 0
		local tile_x_start, tile_y = math.floor(reg_scx / 8), math.floor(reg_scy / 8)
		local x, y = -(reg_scx % 8), -(reg_scy % 8)
		for y = y, 144, 8 do
			local tile_x = tile_x_start
			for x = x, 168, 8 do
				local tile = vram[vram_offset + tile_x + tile_y * 32]
				if signed_addr_mode and tile < 128 then
					tile = tile + 256
				end
				ret.draw_tile(vram, tile, fb, x, y, bgp_0, bgp_1, bgp_2, bgp_3)

				if tile_x == 31 then
					tile_x = 0 -- x wraparound
				else
					tile_x = tile_x + 1
				end
			end

			if tile_y == 31 then
				tile_y = 0 -- y wraparound
			else
				tile_y = tile_y + 1
			end
		end

		local mode8x16 = bitops.tbl_and[0x0401 + reg_lcdc] ~= 0

		local obp0_0, obp0_1, obp0_2, obp0_3 = split_palette(reg_obp0)
		local obp1_0, obp1_1, obp1_2, obp1_3 = split_palette(reg_obp1)

		for oam_offset = 1, 0xA0, 4 do
			local y, x = oam[oam_offset], oam[oam_offset+1]
			if y > 0 and y < 160 and x > 0 and x < 168 then
				local flags = oam[oam_offset+3]
				if bitops.tbl_and[0x1001 + flags] == 0 then
					ret.draw_tile(vram, oam[oam_offset+2], fb, x - 8, y - 16, nil, obp0_1, obp0_2, obp0_3)
				else
					ret.draw_tile(vram, oam[oam_offset+2], fb, x - 8, y - 16, nil, obp1_1, obp1_2, obp1_3)
				end

				if mode8x16 then
					ret.draw_tile(vram, oam[oam_offset+2]+1, fb, x - 8, y - 8, nil, obp0_1, obp0_2, obp0_3)
				else
					ret.draw_tile(vram, oam[oam_offset+2]+1, fb, x - 8, y - 8, nil, obp1_1, obp1_2, obp1_3)
				end
			end
		end
	end

	function ret.read_byte(address)
		--print(string.format("PPU read %04x", address))
		if address == 0xFF40 then
			return reg_lcdc
		elseif address == 0xFF41 then
			return reg_stat + mode
		elseif address == 0xFF42 then
			return reg_scy
		elseif address == 0xFF43 then
			return reg_scx
		elseif address == 0xFF44 then
			return ly
		elseif address == 0xFF47 then
			return reg_bgp
		elseif address == 0xFF48 then
			return reg_obp0
		elseif address == 0xFF49 then
			return reg_obp1
		else
			warn(string.format("UNIMPL: PPU read %04x", address))
			return 0
		end
	end

	function ret.write_byte(address, value)
		--print(string.format("PPU write %04x %02x", address, value))
		if address == 0xFF40 then
			reg_lcdc = value
		elseif address == 0xFF41 then
			reg_stat = bitops.tbl_and[0x7801 + value]
			if reg_stat ~= 0 then
				warn(string.format("UNIMPL: STAT value %02x", reg_stat))
			end
		elseif address == 0xFF42 then
			reg_scy = value
		elseif address == 0xFF43 then
			reg_scx = value
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

	function ret.next_line(mem, fb)
		if reg_lcdc < 0x80 then
			-- PPU off
			ly = 0
			return
		end

		if ly == 144 then
			-- Begin of vblank
			mem.raise_irq(1)

			ret.draw_tilemap(mem.vram, mem.oam, fb)
		end

		if ly >= 144 then
			mode = 1 -- vblank
		else
			mode = 0 -- hblank. mode 2 and 3 not exposed.
		end

		if ly == 153 then
			ly = 0
		else
			ly = ly + 1
		end
	end

	return ret
end
