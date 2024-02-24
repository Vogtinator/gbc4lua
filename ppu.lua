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

	local ret = {}

	function ret.draw_tile(vram, tile, fb, x, y)
		local tile_addr = 1 + tile * 0x10
		local fb_addr = 1 + x + y * 160
		local c_0, c_1, c_2, c_3 = 0, 1, 2, 3 -- TODO
		for y = 0, 7 do
			local pxdata = tbl_expand[1+vram[tile_addr]] + 2 * tbl_expand[1+vram[tile_addr+1]]
			for x = 0, 7 do
				if pxdata >= 0xC000 then
					fb[fb_addr] = c_3
					pxdata = pxdata - 0xC000
				elseif pxdata >= 0x8000 then
					fb[fb_addr] = c_2
					pxdata = pxdata - 0x8000
				elseif pxdata >= 0x4000 then
					fb[fb_addr] = c_1
					pxdata = pxdata - 0x4000
				else
					fb[fb_addr] = c_0
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

	return ret
end
