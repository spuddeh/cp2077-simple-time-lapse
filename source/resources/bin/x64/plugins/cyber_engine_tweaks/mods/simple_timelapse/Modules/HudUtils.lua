-- ======================================================================================
-- Simple Time-lapse - HudUtils Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Hides and restores the HUD by pushing the game's Empty UI context. Most HUD widgets in
-- prototype_hud.inkhud mask that context out, so one push hides the HUD, notifications
-- included, and one pop restores it.
--
-- The vehicle HUD is not one of them: its widgets are visible under VehicleMounted, the
-- context the game pushes on mounting. It has its own game setting, so hiding turns that
-- off and restoring puts back the value it replaced. That setting is the only one this
-- mod writes, and a value changed while the HUD is hidden is left alone.
--
-- These do not move the vehicle HUD, both measured in game: a second Empty context
-- pushed over VehicleMounted, and SetHudEntryForcedVisibility(ForceHide) on the vehicle
-- entries. Swapping the contexts instead of stacking them is worse than useless - it
-- leaves the game's own stack short a context, and the game can crash on the next push.
--
-- The scanner pushes its own context and is left alone: a scanner that cannot be read is
-- worse than a scanner on screen.
-- ======================================================================================

local GameSettings = require("Modules/GameSettings")
local Log = require("Modules/Log")
local HudUtils = {}

local VEHICLE_HUD_SETTING = "/interface/hud/vehicle_hud"

local function EmptyContext()
    return Enum.new("UIGameContext", "Empty")
end

--- Turns the vehicle HUD setting off, remembering what it was.
local function HideVehicleHud(mod)
    local ok, before = pcall(function() return GameSettings.Get(VEHICLE_HUD_SETTING) end)
    if not ok or type(before) ~= "boolean" then
        Log.Warn("Could not read %s, the vehicle HUD is left alone", VEHICLE_HUD_SETTING)
        return
    end
    if before == false then return end

    GameSettings.Set(VEHICLE_HUD_SETTING, false)
    mod.vehicleHudBefore = before
    Log.Debug("Vehicle HUD hidden")
end

--- Puts the setting back, unless something else has turned it on since.
local function RestoreVehicleHud(mod)
    if mod.vehicleHudBefore == nil then return end

    local ok, current = pcall(function() return GameSettings.Get(VEHICLE_HUD_SETTING) end)
    if ok and current == false then
        GameSettings.Set(VEHICLE_HUD_SETTING, mod.vehicleHudBefore)
        Log.Debug("Vehicle HUD restored")
    end
    mod.vehicleHudBefore = nil
end

function HudUtils.Hide(mod)
    if mod.hudHidden then return end
    local uiSystem = Game.GetUISystem()
    if not uiSystem then return end

    uiSystem:PushGameContext(EmptyContext())
    mod.hudHidden = true
    HideVehicleHud(mod)
    Log.Debug("HUD hidden")
end

function HudUtils.Restore(mod)
    if not mod.hudHidden then return end
    local uiSystem = Game.GetUISystem()
    if not uiSystem then return end

    uiSystem:PopGameContext(EmptyContext())
    mod.hudHidden = false
    RestoreVehicleHud(mod)
    Log.Debug("HUD restored")
end

--- Panic button: pops the Empty context whether or not this mod thinks it pushed one,
--- and turns the vehicle HUD setting back on.
function HudUtils.ForceRestore(mod)
    local uiSystem = Game.GetUISystem()
    if uiSystem then uiSystem:PopGameContext(EmptyContext()) end
    pcall(function() GameSettings.Set(VEHICLE_HUD_SETTING, true) end)
    mod.vehicleHudBefore = nil
    mod.hudHidden = false
    Log.Debug("HUD forced back on")
end

function HudUtils.Toggle(mod)
    if mod.hudHidden then
        HudUtils.Restore(mod)
    else
        HudUtils.Hide(mod)
    end
end

return HudUtils
