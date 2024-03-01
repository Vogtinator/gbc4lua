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
	local reg_stat, reg_lyc = 0, 0
	local reg_wx, reg_wy = 0, 0

	-- PPU state
	local ly, mode = 0, 1

	local ret = {}

	-- Draw tile with given palette (nil = transparent)
	-- at given offset (can be out of bounds)
	function ret.draw_tile(vram, tile, fb, x, y, c0, c1, c2, c3, mirror_h, mirror_v)
		local tile_addr = 1 + tile * 0x10
		local y_start, y_end, y_step
		if mirror_v then
			y_start, y_end, y_step = y + 1, y, -1
		else
			y_start, y_end, y_step = y, y + 7, 1
		end
		local x_start, x_end, x_step
		if mirror_h then
			x_start, x_end, x_step = x + 7, x, -1
		else
			x_start, x_end, x_step = x, x + 7, 1
		end

		for ty = y_start, y_end, y_step do
			local pxdata = tbl_expand[1+vram[tile_addr]] + 2 * tbl_expand[1+vram[tile_addr+1]]
			for tx = x_start, x_end, x_step do
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
					fb[1 + ty * 160 + tx] = c
				end
				pxdata = pxdata * 4
			end

			tile_addr = tile_addr + 2
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

		-- Draw the background
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

		-- Draw the window
		if bitops.tbl_and[0x2001 + reg_lcdc] ~= 0 then
			vram_offset = 0x1801
			if bitops.tbl_and[0x4001 + reg_lcdc] ~= 0 then
				vram_offset = 0x1C01
			end

			local tile_y = 0
			x, y = reg_wx - 7, reg_wy
			for y = y, 144, 8 do
				local tile_x = 0
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
		end

		-- Draw objects
		local mode8x16 = bitops.tbl_and[0x0401 + reg_lcdc] ~= 0

		local obp0_0, obp0_1, obp0_2, obp0_3 = split_palette(reg_obp0)
		local obp1_0, obp1_1, obp1_2, obp1_3 = split_palette(reg_obp1)

		for oam_offset = 1, 0xA0, 4 do
			local y, x = oam[oam_offset], oam[oam_offset+1]
			if y > 0 and y < 160 and x > 0 and x < 168 then
				local flags = oam[oam_offset+3]
				local mirror_h, mirror_v = bitops.tbl_and[0x2001 + flags] ~= 0, bitops.tbl_and[0x4001 + flags] ~= 0
				if bitops.tbl_and[0x1001 + flags] == 0 then
					ret.draw_tile(vram, oam[oam_offset+2], fb, x - 8, y - 16, nil, obp0_1, obp0_2, obp0_3, mirror_h, mirror_v)
				else
					ret.draw_tile(vram, oam[oam_offset+2], fb, x - 8, y - 16, nil, obp1_1, obp1_2, obp1_3, mirror_h, mirror_v)
				end

				if mode8x16 then
					ret.draw_tile(vram, oam[oam_offset+2]+1, fb, x - 8, y - 8, nil, obp0_1, obp0_2, obp0_3, mirror_h, mirror_v)
				else
					ret.draw_tile(vram, oam[oam_offset+2]+1, fb, x - 8, y - 8, nil, obp1_1, obp1_2, obp1_3, mirror_h, mirror_v)
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
		elseif address == 0xFF45 then
			return reg_lyc
		elseif address == 0xFF47 then
			return reg_bgp
		elseif address == 0xFF48 then
			return reg_obp0
		elseif address == 0xFF49 then
			return reg_obp1
		elseif address == 0xFF4A then
			return reg_wy
		elseif address == 0xFF4B then
			return reg_wx
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
		elseif address == 0xFF45 then
			reg_lyc = value
		elseif address == 0xFF47 then
			reg_bgp = value
		elseif address == 0xFF48 then
			reg_obp0 = value
		elseif address == 0xFF49 then
			reg_obp1 = value
		elseif address == 0xFF4A then
			reg_wy = value
		elseif address == 0xFF4B then
			reg_wx = value
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

		if ly == reg_lyc then
			mode = mode + 4 -- LYC == LY bit in STAT
			if reg_stat >= 0x40 then
				mem.raise_irq(2)
			end
		end
	end

	return ret
end
