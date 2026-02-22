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
local HudUtils = {}

--- Gets the native HUD group object safely.
function HudUtils.GetHudGroup()
    if not GameSettings then return nil end
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
        print("[Time-lapse] HUD Hidden (Snapshot Saved)")
    end
end

--- Restores the HUD from snapshot.
function HudUtils.Restore(mod)
    if not GameSettings then return end

    GameSettings.ImportVars(mod.hudSettingsSnapshot)

    mod.hudHidden = false
    print("[Time-lapse] HUD Restored")
end

--- Force Restore (Panic Button).
function HudUtils.ForceRestore(mod)
    if not GameSettings then return end

    GameSettings.SetGroupBool('/interface/hud', true)

    mod.hudHidden = false
    print("[Time-lapse] HUD Force Restored (All On)")
end

function HudUtils.Toggle(mod)
    if mod.settings.autoHideHud then
        mod.settings.autoHideHud = false
        print("[Time-lapse] Auto-Hide disabled due to manual toggle.")
    end

    if mod.hudHidden then
        HudUtils.Restore(mod)
    else
        HudUtils.Hide(mod)
    end
end

return HudUtils
