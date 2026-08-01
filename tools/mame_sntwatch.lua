-- Reference measurement: inject a speech request, then watch BOTH sides.
--   host side : the two OP4 writes (low nibble + strobe, then high nibble)
--   board side: what the 6802 actually READS from PIA2 port A, and when,
--               plus its writes to the TMS5200 data port (PIA1 port A).
-- This is the ground truth our RTL has to reproduce.
local m = manager.machine
local main = m.devices[":maincpu"]
local snt = m.devices[":snt:cpu"]
local mainpc = main.state["PC"]
local sntpc = snt.state["PC"]
local mem = main.spaces["program"]

local function now()
   local ok, v = pcall(function() return m.time:as_double() end)
   return ok and v or 0
end

local t0 = nil
local function rel()
   local t = now()
   return t0 and (t - t0) * 1e6 or 0
end

TAP1 = main.spaces["io"]:install_write_tap(0x00, 0x1f, "op4",
   function(offset, data, mask)
      if offset >= 4 and offset <= 7 then
         print(string.format("  HOST  +%8.1fus OP4=%02X nib=%2d strobe=%d",
            rel(), data, data & 0x0f, (data >> 4) & 1))
      end
   end)

-- PIA2 port A at $0080 is the command port the handler reads twice
TAP2 = snt.spaces["program"]:install_read_tap(0x0080, 0x0080, "pia2a",
   function(offset, data, mask)
      print(string.format("  BOARD +%8.1fus READ PIA2A = %02X   (pc=$%04X)",
         rel(), data, sntpc.value))
   end)

-- PIA1 port A at $0090 is the TMS5200 data bus
local wr = 0
TAP3 = snt.spaces["program"]:install_write_tap(0x0090, 0x0090, "tmsdata",
   function(offset, data, mask)
      wr = wr + 1
      if wr <= 8 then
         print(string.format("  BOARD +%8.1fus WRITE TMS  = %02X   (pc=$%04X)",
            rel(), data, sntpc.value))
      end
   end)

local f = 0
local fired = 0
local cmds = { 0x32, 0x2B, 0x38 }
emu.register_frame_done(function()
   f = f + 1
   if f > 300 and f % 120 == 0 and fired < #cmds then
      fired = fired + 1
      wr = 0
      t0 = now()
      print(string.format("\n>>> speak($%02X)  (low nib=%d, high nib=%d)",
         cmds[fired], cmds[fired] & 0x0f, cmds[fired] >> 4))
      mem:write_u8(0xE4D6, cmds[fired])
      mem:write_u8(0xE420, mem:read_u8(0xE420) | 0x10)
   end
end)
print("SNTWATCH INSTALLED")
