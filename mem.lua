function mem_init(bootrom, rom, ppu, bitops)
	local bootrom_visible = bootrom ~= nil

	local ppu_read_byte = ppu.read_byte
	local ppu_write_byte = ppu.write_byte

	local reg_if, reg_ie = 0, 0

	local reg_joyp = 0
	-- Lower nibble of ^ depending on selected column
	local joyp_arrows, joyp_action = 0xF, 0xF

	-- Selected rom bank minus one
	local rom_bank = 0
	-- Whether ext ram is enabled and the selected ext ram bank
	local extram_enabled, extram_bank = false, 0

	local ret = {}

	local wram = {}
	for i = 1, 0x2000, 1 do
		wram[i] = 0
	end

	local hram = {}
	for i = 1, 0x7F, 1 do
		hram[i] = 0
	end

	local vram = {}
	ret.vram = vram
	for i = 1, 0x2000 do
		vram[i] = 0
	end

	local oam = {}
	ret.oam = oam
	for i = 1, 0xA0 do
		oam[i] = 0
	end

	local extram = {}
	for i = 1, 0x8000 do
		extram[i] = 0
	end

	if rom[1+0x147] > 3 then
		warn(string.format("Cartridge type 0x%02x not supported", rom[1+0x147]))
	end

	-- Key constants for joyp_press and joyp_release
	ret.btn_a, ret.btn_right = 1, 1
	ret.btn_b, ret.btn_left = 2, 2
	ret.btn_select, ret.btn_up = 4, 4
	ret.btn_start, ret.btn_down = 8, 8

	function update_joyp()
		-- Keep only matrix select lines
		reg_joyp = bitops.tbl_and[0x3001 + reg_joyp]

		if reg_joyp == 0x30 then
			reg_joyp = reg_joyp + 0xF
		elseif reg_joyp == 0x20 then
			reg_joyp = reg_joyp + joyp_arrows
		elseif reg_joyp == 0x10 then
			reg_joyp = reg_joyp + joyp_action
		else
			warn("Both joyp columns selected")
		end
	end

	function ret.joyp_press(arrows, action)
		-- Clear bits
		joyp_arrows = joyp_arrows - bitops.tbl_and[1 + 0x100*joyp_arrows + arrows]
		joyp_action = joyp_action - bitops.tbl_and[1 + 0x100*joyp_action + action]
		update_joyp()
	end

	function ret.joyp_release(arrows, action)
		-- Set bits
		joyp_arrows = bitops.tbl_or[1 + 0x100*joyp_arrows + arrows]
		joyp_action = bitops.tbl_or[1 + 0x100*joyp_action + action]
		update_joyp()
	end

	function ret.read_byte(address)
		--if address < 0x100 and bootrom_visible then
		--	return bootrom[1 + address]
		--end

		if address < 0x4000 then
			return rom[1 + address]
		end

		if address < 0x8000 then
			return rom[1 + address + rom_bank * 0x4000]
		end

		if address < 0xA000 then
			return vram[address - 0x7FFF]
		end

		if address < 0xC000 and extram_enabled then
			return extram[address - 0x9FFF + extram_bank * 0x2000]
		end

		if address >= 0xC000 and address < 0xE000 then
			return wram[address - 0xBFFF]
		end

		if address == 0xFF0F then
			return reg_if
		end

		if address == 0xFF00 then
			return reg_joyp
		end

		if address >= 0xFF40 and address < 0xFF70 then
			return ppu_read_byte(address)
		end

		if address >= 0xFF80 and address < 0xFFFF then
			return hram[address - 0xFF7F]
		end

		if address == 0xFFFF then
			return reg_ie
		end

		warn(string.format("UNIMPL: read_byte 0x%04x", address))
		return 0
	end
	local read_byte = ret.read_byte

	local sb = 0

	function ret.write_byte(address, value)
		--print(string.format("%04x <- %02x", address, value))

		if address < 0x2000 then
			extram_enabled = bitops.tbl_and[0x0F01 + value] == 0x0A
			return
		end

		if address >= 0x2000 and address < 0x4000 then
			if value == 0 then
				rom_bank = 0
			elseif value < 0x20 then
				rom_bank = value - 1
			else
				print("UNIMPL: High rom bank bits")
			end
			return
		end

		if address >= 0x4000 and address < 0x6000 then
			extram_bank = bitops.tbl_and[0x0301 + value]
			return
		end

		if address >= 0x8000 and address < 0xA000 then
			vram[address - 0x7FFF] = value
			return
		end

		if address < 0xC000 and extram_enabled then
			extram[address - 0x9FFF + extram_bank * 0x2000] = value
			return
		end

		if address >= 0xC000 and address < 0xE000 then
			wram[address - 0xBFFF] = value
			return
		end

		if address >= 0xFE00 and address < 0xFEA0 then
			oam[address - 0xFDFF] = value
			return
		end

		if address >= 0xFEA0 and address < 0xFF00 then
			return -- ignore
		end

		if address == 0xFF00 then
			reg_joyp = value
			update_joyp()
			return
		end

		if address == 0xFF01 then
			sb = value
			return
		end

		if address == 0xFF02 and value == 0x81 then
			if sb >= 0x80 then
				sb = sb - 0x80
			end
			print(string.format("Recv: %c", sb))
			return
		end

		if address == 0xFF0F then
			reg_if = value
			return
		end

		if address >= 0xFF40 and address < 0xFF70 then
			if address == 0xFF46 then
				-- OAM DMA. Recognize and speed up wait loops here?
				local src = value * 0x100
				for off = 0, 0x9F do
					oam[1+off] = read_byte(src + off)
				end
				return
			end

			return ppu_write_byte(address, value)
		end

		if address >= 0xFF80 and address < 0xFFFF then
			hram[address - 0xFF7F] = value
			return
		end

		if address == 0xFFFF then
			reg_ie = value
			return
		end

		warn(string.format("UNIMPL: write_byte 0x%04x value %02x", address, value))
		return
	end
	local write_byte = ret.write_byte

	function ret.read_word(address)
		return read_byte(address) + 0x100*read_byte(address + 1)
	end

	function ret.write_word(address, value)
		write_byte(address, value % 0x100)
		write_byte(address + 1, math.floor(value / 0x100))
	end

	function ret.has_bootrom()
		return bootrom ~= nil
	end

	function ret.get_rom_bank(pc)
		if pc >= 0x4000 then
			return rom_bank + 1
		else
			return 0
		end
	end

	-- Sets the corresponding bits in reg_if
	function ret.raise_irq(bits)
		reg_if = bitops.tbl_or[1 + 0x100*bits + reg_if]
	end

	-- Returns the number of the lowest set bit in reg_if&reg_ie
	-- and clears it in reg_if
	function ret.next_irq()
		if reg_if == 0 or reg_ie == 0 then
			return nil
		end

		local pending = bitops.tbl_and[1 + 0x100*reg_if + reg_ie]
		if pending == 0 then
			return nil
		end

		local mask = 0x01
		for bit = 0, 5 do
			if bitops.tbl_and[1 + 0x100*pending + mask] ~= 0 then
				reg_if = reg_if - mask
				return bit
			end
			mask = mask * 2
		end

		assert(false, "unreachable")
	end

	return ret
end
