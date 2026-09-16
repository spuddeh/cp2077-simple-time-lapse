-- ======================================================================================
-- Simple Time-lapse - HudUtils Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Hides and restores the HUD by pushing the game's Empty UI context. Most HUD widgets in
-- prototype_hud.inkhud mask that context out, so one push hides the HUD, notifications
-- included, and one pop restores it. A context the game pushes on top, the scanner's
-- among them, decides visibility until it pops.
--
-- The vehicle HUD is visible under VehicleMounted and only its game setting moves it, so
-- hiding turns /interface/hud/vehicle_hud off. That setting is written to the player's
-- config the moment it changes and it is the one setting this mod writes, so the value it
-- replaced is saved with the mod's settings and put back on the next launch when a crash
-- leaves it off. A value changed while the HUD is hidden belongs to whoever changed it.
-- ======================================================================================

local GameSettings = require("Modules/GameSettings")
local Log = require("Modules/Log")
local Settings = require("Modules/Settings")
local HudUtils = {}

local VEHICLE_HUD_SETTING = "/interface/hud/vehicle_hud"

local function EmptyContext()
    return Enum.new("UIGameContext", "Empty")
end

local function ReadVehicleHud()
    local ok, value = pcall(function() return GameSettings.Get(VEHICLE_HUD_SETTING) end)
    if ok and type(value) == "boolean" then return value end
    return nil
end

--- Turns the vehicle HUD setting off, and records the value to put back.
local function HideVehicleHud(mod)
    local before = ReadVehicleHud()
    if before == nil then
        Log.Warn("Could not read %s, the vehicle HUD is left alone", VEHICLE_HUD_SETTING)
        return
    end
    if before == false then return end

    GameSettings.Set(VEHICLE_HUD_SETTING, false)
    mod.settings.vehicleHudPending = true
    mod.settings.vehicleHudRestore = before
    Settings.Save(mod)
    Log.Debug("Vehicle HUD hidden")
end

--- Puts the setting back, unless something else has turned it on since.
local function RestoreVehicleHud(mod)
    if not mod.settings.vehicleHudPending then return end

    if ReadVehicleHud() == false then
        GameSettings.Set(VEHICLE_HUD_SETTING, mod.settings.vehicleHudRestore)
        Log.Debug("Vehicle HUD restored")
    end
    mod.settings.vehicleHudPending = false
    Settings.Save(mod)
end

--- Puts the vehicle HUD back after a session that ended with it hidden. Call once, after
--- the settings load.
function HudUtils.Repair(mod)
    if not mod.settings.vehicleHudPending then return end

    if ReadVehicleHud() == false then
        GameSettings.Set(VEHICLE_HUD_SETTING, mod.settings.vehicleHudRestore)
        Log.Info("Vehicle HUD was left hidden by the previous session, put back")
    end
    mod.settings.vehicleHudPending = false
    Settings.Save(mod)
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
    mod.settings.vehicleHudPending = false
    Settings.Save(mod)
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
