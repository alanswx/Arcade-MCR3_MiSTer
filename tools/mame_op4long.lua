-- Long dotrone session with varied play, logging the main-CPU PC at every
-- OP4 write so we learn WHICH of the 12 OUT ($04),A sites actually fire and
-- whether any of them ever sets bit 4 (the speech strobe).
local m = manager.machine

local ip0 = m.ioport.ports[":ssio:IP0"]
local ip2 = m.ioport.ports[":ssio:IP2"]
local ip1 = m.ioport.ports[":ssio:IP1"]
local coin  = ip0.fields["Coin 1"]
local start = ip0.fields["1 Player Start"]
local fire  = ip0.fields["P1 Button 1"]
local fire2 = ip2.fields["P1 Button 2"]
local up    = ip2.fields["P1 Up"]
local down  = ip2.fields["P1 Down"]
local left  = ip2.fields["P1 Left"]
local right = ip2.fields["P1 Right"]
local aimu  = ip2.fields["Aim Up"]
local aimd  = ip2.fields["Aim Down"]

local cpu = m.devices[":maincpu"]
local pcst = cpu.state["PC"]

local function now()
   local ok, v = pcall(function() return m.time:as_double() end)
   return ok and v or 0
end

local sites = {}
local strobes = 0
TAP = cpu.spaces["io"]:install_write_tap(0x00, 0x1f, "op4pc",
   function(offset, data, mask)
      if offset >= 4 and offset <= 7 then
         local pc = pcst.value
         local key = string.format("%04X", pc)
         sites[key] = (sites[key] or 0) + 1
         if (data & 0x10) ~= 0 then
            strobes = strobes + 1
            print(string.format("*** STROBE t=%9.5f pc=$%04X data=%02X nib=%2d",
               now(), pc, data, data & 0x0f))
         end
      end
   end)

local f = 0
local rng = 12345
local function rnd(n) rng = (rng * 1103515245 + 12345) % 2147483648; return rng % n end
emu.register_frame_done(function()
   f = f + 1
   -- keep feeding coins and starts so a finished game restarts
   if f % 1800 == 100 then coin:set_value(1) end
   if f % 1800 == 112 then coin:set_value(0) end
   if f % 1800 == 200 then start:set_value(1) end
   if f % 1800 == 212 then start:set_value(0) end
   if f > 250 then
      up:set_value(rnd(8) == 0 and 1 or 0)
      down:set_value(rnd(8) == 0 and 1 or 0)
      left:set_value(rnd(8) == 0 and 1 or 0)
      right:set_value(rnd(8) == 0 and 1 or 0)
      fire:set_value(rnd(5) == 0 and 1 or 0)
      fire2:set_value(rnd(6) == 0 and 1 or 0)
      aimu:set_value(rnd(9) == 0 and 1 or 0)
      aimd:set_value(rnd(9) == 0 and 1 or 0)
   end
   if f % 3000 == 0 then
      print(string.format("--- frame %d t=%.1f strobes=%d ---", f, now(), strobes))
      m.video:snapshot()
   end
end)

emu.register_stop(function()
   print("=== OP4 write sites (PC -> count) ===")
   local ks = {}
   for k in pairs(sites) do ks[#ks+1] = k end
   table.sort(ks)
   for _, k in ipairs(ks) do print(string.format("   pc=$%s  %d writes", k, sites[k])) end
   print(string.format("=== TOTAL STROBES (bit4 set): %d ===", strobes))
end)
print("OP4LONG INSTALLED")
