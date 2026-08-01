-- PURE ATTRACT MODE, no input at all.
-- speak() at $7DF9 only proceeds when ($E517)==0, so if speech is an attract
-- feature this run will show strobes with no coin ever inserted.
-- Watches: OP4 strobes, the command byte $E4D6, and the gate $E517.
local m = manager.machine
local cpu = m.devices[":maincpu"]
local pcst = cpu.state["PC"]

local function now()
   local ok, v = pcall(function() return m.time:as_double() end)
   return ok and v or 0
end

local strobes = 0
TAP1 = cpu.spaces["io"]:install_write_tap(0x00, 0x1f, "op4",
   function(offset, data, mask)
      if offset >= 4 and offset <= 7 and (data & 0x10) ~= 0 then
         strobes = strobes + 1
         print(string.format("*** STROBE t=%9.5f pc=$%04X data=%02X nib=%2d",
            now(), pcst.value, data, data & 0x0f))
      end
   end)

TAP2 = cpu.spaces["program"]:install_write_tap(0xE4D6, 0xE4D6, "cmd",
   function(offset, data, mask)
      print(string.format("CMD   t=%9.5f pc=$%04X  $E4D6 <- %02X", now(), pcst.value, data))
   end)

local last517 = nil
TAP3 = cpu.spaces["program"]:install_write_tap(0xE517, 0xE517, "gate",
   function(offset, data, mask)
      if data ~= last517 then
         last517 = data
         print(string.format("GATE  t=%9.5f pc=$%04X  $E517 <- %02X %s", now(),
            pcst.value, data, data == 0 and "(speech ENABLED)" or "(speech blocked)"))
      end
   end)

local f = 0
emu.register_frame_done(function()
   f = f + 1
   if f % 1800 == 0 then
      print(string.format("--- frame %d t=%.1f strobes=%d ---", f, now(), strobes))
      m.video:snapshot()
   end
end)
print("ATTRACT WATCH INSTALLED")
