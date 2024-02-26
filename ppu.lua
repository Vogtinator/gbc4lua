function ppu_init()
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

	-- reg_bgp split up
	local bgp_0, bgp_1, bgp_2, bgp_3 = 0, 0, 0, 0

	-- PPU state
	local ly = 0

	local ret = {}

	function ret.draw_tile(vram, tile, fb, x, y)
		local tile_addr = 1 + tile * 0x10
		local fb_addr = 1 + x + y * 160
		for y = 0, 7 do
			local pxdata = tbl_expand[1+vram[tile_addr]] + 2 * tbl_expand[1+vram[tile_addr+1]]
			for x = 0, 7 do
				if pxdata >= 0xC000 then
					fb[fb_addr] = bgp_3
					pxdata = pxdata - 0xC000
				elseif pxdata >= 0x8000 then
					fb[fb_addr] = bgp_2
					pxdata = pxdata - 0x8000
				elseif pxdata >= 0x4000 then
					fb[fb_addr] = bgp_1
					pxdata = pxdata - 0x4000
				else
					fb[fb_addr] = bgp_0
				end
				pxdata = pxdata * 4
				fb_addr = fb_addr + 1
			end

			tile_addr = tile_addr + 2
			fb_addr = fb_addr + 160 - 8
		end
	end

	function ret.draw_tilemap(vram, fb)
		for y = 0, 17 do
			for x = 0, 19 do
				ret.draw_tile(vram, vram[0x1801 + x + y * 32], fb, x * 8, y * 8)
				--ret.draw_tile(vram, x + y * 20, fb, x * 8, y * 8)
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

			local bgp = reg_bgp
			bgp_0 = bgp % 4
			bgp = (bgp - bgp_0) / 4
			bgp_1 = bgp % 4
			bgp = (bgp - bgp_1) / 4
			bgp_2 = bgp % 4
			bgp = (bgp - bgp_2) / 4
			bgp_3 = bgp % 4
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
