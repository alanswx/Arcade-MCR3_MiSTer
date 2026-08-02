-- Clean single-phrase reference capture from MAME.
-- Injects ONE speech command at a known time and prints that time, so the
-- exact segment can be cut out of the -wavwrite file afterwards. The command
-- byte comes in via CMDBYTE so the same script serves every phrase.
local m = manager.machine
local cpu = m.devices[":maincpu"]
local mem = cpu.spaces["program"]

local CMDS = os.getenv("CMDBYTE") or "0x2B"
local CMD = (CMDS == "none") and nil or tonumber(CMDS)

local function now()
   local ok, v = pcall(function() return m.time:as_double() end)
   return ok and v or 0
end

-- watch the TMS data bus so we can report when speech actually streamed
local wr = 0
TAP = m.devices[":snt:cpu"].spaces["program"]:install_write_tap(
   0x0090, 0x0090, "tms", function() wr = wr + 1 end)

local f = 0
local fired = false
emit_t = 0
emu.register_frame_done(function()
   f = f + 1
   if f == 600 and not fired and CMD then
      fired = true
      emit_t = now()
      print(string.format("INJECT $%02X at t=%.4f", CMD, emit_t))
      mem:write_u8(0xE4D6, CMD)
      mem:write_u8(0xE420, mem:read_u8(0xE420) | 0x10)
   end
end)

emu.register_stop(function()
   print(string.format("RESULT cmd=$%02X inject_t=%.4f tms_writes=%d", CMD, emit_t, wr))
end)
print("REF_ONE INSTALLED")
