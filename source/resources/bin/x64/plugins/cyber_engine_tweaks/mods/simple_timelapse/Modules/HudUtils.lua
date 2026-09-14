-- ======================================================================================
-- Simple Time-lapse - HudUtils Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Hides and restores the HUD by pushing the game's Empty UI context. Every HUD widget
-- in prototype_hud.inkhud masks that context out except the FPS counter, so one push
-- hides the HUD, notifications included, and one pop restores it. No user setting changes.
-- A context the game pushes on top (scanner, popups, vehicles) decides visibility until it pops.
-- ======================================================================================

local Log = require("Modules/Log")
local HudUtils = {}

local function EmptyContext()
    return Enum.new("UIGameContext", "Empty")
end

function HudUtils.Hide(mod)
    if mod.hudHidden then return end
    local uiSystem = Game.GetUISystem()
    if not uiSystem then return end

    uiSystem:PushGameContext(EmptyContext())
    mod.hudHidden = true
    Log.Debug("HUD hidden")
end

function HudUtils.Restore(mod)
    if not mod.hudHidden then return end
    local uiSystem = Game.GetUISystem()
    if not uiSystem then return end

    uiSystem:PopGameContext(EmptyContext())
    mod.hudHidden = false
    Log.Debug("HUD restored")
end

--- Panic button: pops the Empty context whether or not this mod thinks it pushed one.
function HudUtils.ForceRestore(mod)
    local uiSystem = Game.GetUISystem()
    if uiSystem then uiSystem:PopGameContext(EmptyContext()) end
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
