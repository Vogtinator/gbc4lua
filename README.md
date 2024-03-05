GameBoy emulator targeting Lua 5.1
=

How to run with [LÖVE](https://love2d.org):

```
make
love . tetris.gb
```

Controls:

Arrows: WASD  
A/B: J/K  
Start/Select: Return/Space

How to build for Nspire:

```
<git clone of Ndless>/ndless/src/tools/LuaBin/luabin tetris.gb - rom | sed 's/&quot;/"/g' > rom.lua
make gbc4lua.tns
```

Minimum OS version is technically 3.1, but until 3.6 (?) the OS just crashes immediately on open.

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

TODO
-
* Input handling in main_nspire.lua
* Save/load sram contents to variables
* Optimize! For now most parts are not optimized, especially tile/object drawing and blitting to the screen. The code could benefit from loop unrolling and inlining as well.

Writing fast Lua code
-

The Lua language has various traps which slow code down and need to be avoided to get code that's just slow instead of abysmally slow:

* Use locals and function parameters if possible. Access to global variables does a table lookup, access to upvalues is a GETUPVALUE for each read and SETUPVALUE for each write.
* Perform obvious simplifications like constant folding and avoiding redundant reads/writes. There is no optimization performed by the interpreter.
* Avoid table lookups. Cache them if possible, e.g. outside a loop or even outside of a function.
* Unroll loops
* Avoid accessing tables at [0] if not needed. The array part is `tbl[1]`-`tbl[#tbl]`, using `tbl[0]` does a hash lookup.