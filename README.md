GameBoy emulator targeting Lua 5.1
----------------------------------

How to run with LÖVE:

```
make
love . tetris.gb
```

How to build for Nspire:

```
<git clone of Ndless>/ndless/src/tools/LuaBin/luabin tetris.gb - rom | sed 's/&quot;/"/g' > rom.lua
make gbc4lua.tns
```
