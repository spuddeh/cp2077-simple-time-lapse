-- ======================================================================================
-- Simple Time-lapse - HudUtils Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Handles the saving, hiding, and restoring of HUD elements.
-- Relies on GameSettings.lua for recursive logic.
--
-- CREDITS:
-- - Logic inspired by "SimpleToggleHUD" by Mokuppo.
-- - Built using CET Kit by psiberx.
-- ======================================================================================

local GameSettings = require("Modules/GameSettings")
local Log = require("Modules/Log")
local HudUtils = {}

--- Gets the native HUD group object safely.
function HudUtils.GetHudGroup()
    local sys = Game.GetSettingsSystem()
    if not sys then return nil end
    return sys:GetGroup(CName.new('/interface/hud'))
end

--- Hides the HUD after saving a snapshot.
function HudUtils.Hide(mod)
    local hudGroup = HudUtils.GetHudGroup()
    if hudGroup then
        if not mod.hudHidden then
            mod.hudSettingsSnapshot = GameSettings.ExportVars(nil, hudGroup)
        end

        GameSettings.SetGroupBool('/interface/hud', false)

        mod.hudHidden = true
        Log.Debug("HUD hidden, snapshot saved")
    end
end

--- Restores the HUD from snapshot.
function HudUtils.Restore(mod)
    GameSettings.ImportVars(mod.hudSettingsSnapshot)

    mod.hudHidden = false
    Log.Debug("HUD restored")
end

--- Force Restore (Panic Button).
function HudUtils.ForceRestore(mod)
    GameSettings.SetGroupBool('/interface/hud', true)

    mod.hudHidden = false
    Log.Debug("HUD forced fully on")
end

function HudUtils.Toggle(mod)
    if mod.settings.autoHideHud then
        mod.settings.autoHideHud = false
        Log.Debug("Auto-Hide HUD turned off by the Toggle HUD hotkey")
    end

    if mod.hudHidden then
        HudUtils.Restore(mod)
    else
        HudUtils.Hide(mod)
    end
end

return HudUtils
