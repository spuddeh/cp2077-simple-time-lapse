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
-- The vehicle widgets are visible under VehicleMounted, a context the game pushes above
-- the Empty one on mounting, so a second Empty goes on top of it the moment a vehicle HUD
-- spawns. Restore pops that one too, which keeps the pushes and pops balanced however
-- many times the player gets in and out.
--
-- The scanner pushes its own context too, and is left alone: a scanner that cannot be
-- read is worse than a scanner on screen.
-- ======================================================================================

local Log = require("Modules/Log")
local HudUtils = {}

local function EmptyContext()
    return Enum.new("UIGameContext", "Empty")
end

--- Puts an Empty context above the vehicle's, once, while the HUD is meant to be hidden.
local function CoverVehicleHud(mod)
    if mod.vehicleHudCovered then return end
    local uiSystem = Game.GetUISystem()
    if not uiSystem then return end

    uiSystem:PushGameContext(EmptyContext())
    mod.vehicleHudCovered = true
    Log.Debug("HUD: covered the vehicle context")
end

local function UncoverVehicleHud(mod)
    if not mod.vehicleHudCovered then return end
    local uiSystem = Game.GetUISystem()
    if not uiSystem then return end

    uiSystem:PopGameContext(EmptyContext())
    mod.vehicleHudCovered = false
    Log.Debug("HUD: uncovered the vehicle context")
end

--- Watches for a vehicle HUD spawning while the HUD is hidden. Registered once, because
--- an observer cannot be taken off again.
function HudUtils.Init(mod)
    local function OnVehicleHud()
        if mod.hudHidden then CoverVehicleHud(mod) end
    end

    Observe("hudCarController", "OnInitialize", OnVehicleHud)
    Observe("inkMotorcycleHUDGameController", "OnInitialize", OnVehicleHud)
end

function HudUtils.Hide(mod)
    if mod.hudHidden then return end
    local uiSystem = Game.GetUISystem()
    if not uiSystem then return end

    uiSystem:PushGameContext(EmptyContext())
    mod.hudHidden = true
    Log.Debug("HUD hidden")

    -- Already in a vehicle: its HUD is on screen now, not on a later spawn.
    local player = Game.GetPlayer()
    if player and player:IsInVehicle() then CoverVehicleHud(mod) end
end

function HudUtils.Restore(mod)
    if not mod.hudHidden then return end
    local uiSystem = Game.GetUISystem()
    if not uiSystem then return end

    UncoverVehicleHud(mod)
    uiSystem:PopGameContext(EmptyContext())
    mod.hudHidden = false
    Log.Debug("HUD restored")
end

--- Panic button: pops what this mod pushes, whether or not it thinks it pushed them.
function HudUtils.ForceRestore(mod)
    local uiSystem = Game.GetUISystem()
    if uiSystem then
        if mod.vehicleHudCovered then uiSystem:PopGameContext(EmptyContext()) end
        uiSystem:PopGameContext(EmptyContext())
    end
    mod.vehicleHudCovered = false
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
