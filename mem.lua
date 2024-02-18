function mem_init(bootrom, rom)
	local ret = {}

	local read_byte =  function (address)
		if address < 0x100 then
			return bootrom[1 + address]
		end

		print("UNIMPL: read_byte " .. address)
		return 0
	end

	local write_byte = function (address, value)
		print("UNIMPL: write_byte " .. address .. " value")
		return
	end

	local read_word = function (address)
		return read_byte(address) + 0x100*read_byte(address + 1)
	end

	local write_word = function (address, value)
		write_byte(address, value % 0x100)
		write_byte(address + 1, value / 0x100)
	end

	return {
		read_byte = read_byte,
		write_byte = write_byte,
		read_word = read_word,
		write_word = write_word
	}
end
