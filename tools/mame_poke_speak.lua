-- Force a speech request the way the game's own speak() does -- store the
-- command byte in $E4D6 and set bit 4 of the request flags at $E420 -- then
-- log the OP4 writes the game's OWN routines produce.
--
-- This settles the ordering question: $9548 sends the HIGH nibble with the
-- strobe LOW, $993E sends the LOW nibble with the strobe HIGH. Which one
-- reaches the board first, and how far apart, decides what byte the 6802
-- assembles from its two PIA reads.
local m = manager.machine
local cpu = m.devices[":maincpu"]
local pcst = cpu.state["PC"]
local mem = cpu.spaces["program"]

local function now()
   local ok, v = pcall(function() return m.time:as_double() end)
   return ok and v or 0
end

local last = nil
TAP = cpu.spaces["io"]:install_write_tap(0x00, 0x1f, "op4",
   function(offset, data, mask)
      if offset >= 4 and offset <= 7 then
         local t = now()
         local dt = last and (t - last) * 1e6 or 0
         last = t
         print(string.format("OP4 t=%9.5f dt=%8.1fus pc=$%04X data=%02X nib=%2d strobe=%d",
            t, dt, pcst.value, data, data & 0x0f, (data >> 4) & 1))
      end
   end)

local f = 0
local fired = 0
emu.register_frame_done(function()
   f = f + 1
   -- once the game is well past init, inject a speech request every 2s
   if f > 300 and f % 60 == 0 and fired < 6 then
      local cmds = { 0x32, 0x30, 0x2B, 0x2E, 0x33, 0x38 }
      fired = fired + 1
      local c = cmds[fired]
      print(string.format(">>> inject speak($%02X) at t=%.3f", c, now()))
      mem:write_u8(0xE4D6, c)
      local flags = mem:read_u8(0xE420)
      mem:write_u8(0xE420, flags | 0x10)
   end
end)
print("POKE INSTALLED")
