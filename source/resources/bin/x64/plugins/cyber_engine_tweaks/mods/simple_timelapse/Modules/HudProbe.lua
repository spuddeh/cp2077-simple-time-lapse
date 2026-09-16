-- ======================================================================================
-- Simple Time-lapse - HudProbe Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- At the Debug log level, reports what the HUD is doing: every UI game context pushed,
-- popped or swapped by anything in the game, the stack that results, and the state of
-- every /interface/hud setting. The Debug tab's Log HUD State button samples the same
-- thing on demand, which is the only way to read the state while sitting in a vehicle.
-- ======================================================================================

local GameSettings = require("Modules/GameSettings")
local Log = require("Modules/Log")

local HudProbe = {}

-- Mirrors the game's own context stack, built from the pushes and pops seen since the
-- mod loaded. A context pushed before that is not in it.
local stack = {}

-- Every switch in the HUD settings group, which is what the game's HUD menu writes.
local HUD_SETTINGS = {
    "action_buttons", "activity_log", "ammo_counter", "crosshairs", "crouch_indicator",
    "healthbar", "hud_markers", "input_hints", "minimap", "npc_healthbar",
    "npc_nameplates", "npc_names", "object_markers", "quest_tracker", "stamina_oxygen",
    "vehicle_hud", "wanted_level",
}

local function ContextName(context)
    local name = tostring(context)
    return (name:gsub("^UIGameContext%.", ""))
end

local function StackString()
    if #stack == 0 then return "(none seen)" end
    return table.concat(stack, " > ")
end

local function Remove(name)
    for i = #stack, 1, -1 do
        if stack[i] == name then
            table.remove(stack, i)
            return
        end
    end
end

--- Writes the context stack, the mod's own idea of the HUD, and every HUD setting.
function HudProbe.Dump(mod, label)
    if not Log.IsDebug() then return end

    local player = Game.GetPlayer()
    local mounted = player and Game.GetMountedVehicle(player) ~= nil
    Log.Debug("Probe [%s]: stack %s | hudHidden=%s | mounted=%s",
        label, StackString(), tostring(mod.hudHidden), tostring(mounted))

    local parts = {}
    for _, name in ipairs(HUD_SETTINGS) do
        local ok, value = pcall(function() return GameSettings.Get("/interface/hud/" .. name) end)
        parts[#parts + 1] = string.format("%s=%s", name, ok and tostring(value) or "?")
    end
    Log.Debug("Probe [%s]: %s", label, table.concat(parts, " "))
end

--- Registered once, because an observer cannot be taken off again.
function HudProbe.Init(mod)
    Observe("gameuiGameSystemUI", "PushGameContext", function(_, context)
        local name = ContextName(context)
        stack[#stack + 1] = name
        Log.Debug("Probe: push %s | stack %s", name, StackString())
    end)

    Observe("gameuiGameSystemUI", "PopGameContext", function(_, context)
        local name = ContextName(context)
        Remove(name)
        Log.Debug("Probe: pop %s | stack %s", name, StackString())
    end)

    Observe("gameuiGameSystemUI", "SwapGameContext", function(_, oldContext, newContext)
        local oldName, newName = ContextName(oldContext), ContextName(newContext)
        Remove(oldName)
        stack[#stack + 1] = newName
        Log.Debug("Probe: swap %s for %s | stack %s", oldName, newName, StackString())
    end)

    Observe("gameuiGameSystemUI", "ResetGameContext", function()
        stack = {}
        Log.Debug("Probe: reset | stack %s", StackString())
    end)

    Observe("hudCarController", "OnInitialize", function()
        HudProbe.Dump(mod, "car HUD spawned")
    end)

    Observe("inkMotorcycleHUDGameController", "OnInitialize", function()
        HudProbe.Dump(mod, "bike HUD spawned")
    end)

    Observe("vehicleUIGameController", "OnInitialize", function()
        HudProbe.Dump(mod, "vehicle UI spawned")
    end)
end

return HudProbe
