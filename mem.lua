function mem_init(bootrom, rom)
	local bootrom_visible = bootrom ~= nil

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
	for i = 1, 0x2000 do
		vram[i] = 0
	end

	local read_byte = function(address)
		if address < 0x100 and bootrom_visible then
			return bootrom[1 + address]
		end

		if address < 0x4000 then
			return rom[1 + address]
		end

		if address < 0x8000 then
			-- TODO: Bank switching
			return rom[1 + address]
		end

		if address < 0xA000 then
			return vram[address - 0x7FFF]
		end

		if address >= 0xC000 and address < 0xE000 then
			return wram[address - 0xBFFF]
		end

		if address == 0xFF44 then
			-- TODO: LY
			return 0
		end

		if address >= 0xFF80 and address < 0xFFFF then
			return hram[address - 0xFF7F]
		end

		print(string.format("UNIMPL: read_byte 0x%04x", address))
		return 0
	end

	local sb = 0

	local write_byte = function(address, value)
		--print(string.format("%04x <- %02x", address, value))

		if address >= 0x8000 and address < 0xA000 then
			vram[address - 0x7FFF] = value
			return
		end

		if address >= 0xC000 and address < 0xE000 then
			wram[address - 0xBFFF] = value
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

		if address >= 0xFF80 and address < 0xFFFF then
			hram[address - 0xFF7F] = value
			return
		end

		print(string.format("UNIMPL: write_byte 0x%04x value %02x", address, value))
		return
	end

	local read_word = function(address)
		return read_byte(address) + 0x100*read_byte(address + 1)
	end

	local write_word = function(address, value)
		write_byte(address, value % 0x100)
		write_byte(address + 1, math.floor(value / 0x100))
	end

	return {
		has_bootrom = function() return bootrom ~= nil end,
		read_byte = read_byte,
		write_byte = write_byte,
		read_word = read_word,
		write_word = write_word,
		vram = vram
	}
end
