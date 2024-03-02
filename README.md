GameBoy emulator targeting Lua 5.1
=

How to run with [LÖVE](https://love2d.org):

```
make
love . tetris.gb
```

How to build for Nspire:

```
<git clone of Ndless>/ndless/src/tools/LuaBin/luabin tetris.gb - rom | sed 's/&quot;/"/g' > rom.lua
make gbc4lua.tns
```

Not implemented
-

* GBC: Currently it only provides DMG emulation
* Line based rendering: The entire screen is rendered at the beginning of vblank, so raster effects will not work.
* LCD modes: Interrupts and mode status are only partially implemented
* Audio: The Nspire doesn't support audio output
* Timer registers: Implementing those properly would add noticable overhead and it appears like they're not necessary for most games without audio.
* Mapper support: Only MBC1 and MBC5 (without rumble) are implemented
* BG+Window and OBJ enable bits: Everything is always drawn to not rely on line based toggling
* Cycle accurate memory access: Instruction cycles are tracked, but all accesses triggered by an instruction appear to happen within the same cycle. As the timer is not implemented this should not be noticable.
* Cycle accurate interrupts: The CPU only checks for interrupts every line.
* CPU flags for BCD: The N and H flags are not set by instructions other than `pop af`. This will lead to weird score calculations and more.