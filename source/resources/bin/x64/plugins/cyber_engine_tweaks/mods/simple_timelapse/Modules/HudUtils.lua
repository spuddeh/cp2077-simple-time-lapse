-- ======================================================================================
-- Simple Time-lapse - HudUtils Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Hides and restores the HUD by pushing the game's Empty UI context. Most HUD widgets in
-- prototype_hud.inkhud mask that context out, so one push hides the HUD, notifications
-- included, and one pop restores it. No user setting changes.
--
-- The vehicle widgets do not mask it out, so each one is forced hidden by name as well
-- and put back to its own tier rules on restore. A context the game pushes on top, the
-- scanner among them, decides visibility until it pops.
-- ======================================================================================

local Log = require("Modules/Log")
local HudUtils = {}

local function EmptyContext()
    return Enum.new("UIGameContext", "Empty")
end

-- HUD entries from prototype_hud.inkhud that stay visible under the Empty context.
local VEHICLE_ENTRIES = {
    "car hud",
    "motorcycle_hud",
    "driver_combat_hud",
    "car_race_hud",
    "vehicle scan widget",
    "remote_control_driving_hud",
}

--- Forces the vehicle entries hidden, or hands them back to the game's own rules.
local function SetVehicleEntries(uiSystem, visibility)
    local value = Enum.new("worlduiEntryVisibility", visibility)
    for _, entry in ipairs(VEHICLE_ENTRIES) do
        uiSystem:SetHudEntryForcedVisibility(CName.new(entry), value)
    end
end

function HudUtils.Hide(mod)
    if mod.hudHidden then return end
    local uiSystem = Game.GetUISystem()
    if not uiSystem then return end

    uiSystem:PushGameContext(EmptyContext())
    SetVehicleEntries(uiSystem, "ForceHide")
    mod.hudHidden = true
    Log.Debug("HUD hidden")
end

function HudUtils.Restore(mod)
    if not mod.hudHidden then return end
    local uiSystem = Game.GetUISystem()
    if not uiSystem then return end

    uiSystem:PopGameContext(EmptyContext())
    SetVehicleEntries(uiSystem, "TierVisibility")
    mod.hudHidden = false
    Log.Debug("HUD restored")
end

--- Panic button: pops the Empty context and clears the forced entries whether or not
--- this mod thinks it set them.
function HudUtils.ForceRestore(mod)
    local uiSystem = Game.GetUISystem()
    if uiSystem then
        uiSystem:PopGameContext(EmptyContext())
        SetVehicleEntries(uiSystem, "TierVisibility")
    end
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
