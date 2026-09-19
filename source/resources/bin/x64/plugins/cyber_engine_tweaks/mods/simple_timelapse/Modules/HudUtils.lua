-- ======================================================================================
-- Simple Time-lapse - HudUtils Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Hides and restores the HUD by hiding the HUD layer's own window, reached through
-- Codeware's inkSystem. Every HUD widget draws inside it, notifications, the vehicle HUD
-- and the scanner included, and the game never sets its visibility, so it stays hidden
-- whatever context the game pushes. No user setting and no UI context changes.
--
-- The layer is resolved on every call rather than cached, because a new session builds
-- a new one. Without Codeware there is no layer to reach and the HUD is left alone.
-- ======================================================================================

local Log = require("Modules/Log")
local HudUtils = {}

local warnedMissing = false

--- The HUD layer's window, or nil when Codeware is missing or no session is running.
local function LayerWindow()
    local ok, window = pcall(function()
        return Game.GetInkSystem():GetLayer(CName.new("inkHUDLayer")):GetVirtualWindow()
    end)
    if ok and window then return window end
    return nil
end

--- True when Codeware is installed, so the HUD can be hidden at all.
function HudUtils.IsAvailable()
    local ok, inkSystem = pcall(function() return Game.GetInkSystem() end)
    return ok and inkSystem ~= nil
end

local function SetHudVisible(visible)
    local window = LayerWindow()
    if not window then
        if not warnedMissing then
            Log.Warn("The HUD layer is out of reach, so the HUD is left alone. Hiding it needs Codeware")
            warnedMissing = true
        end
        return false
    end
    window:SetVisible(visible)
    return true
end

function HudUtils.Hide(mod)
    if mod.hudHidden then return end
    if not SetHudVisible(false) then return end
    mod.hudHidden = true
    Log.Debug("HUD hidden")
end

function HudUtils.Restore(mod)
    if not mod.hudHidden then return end
    SetHudVisible(true)
    mod.hudHidden = false
    Log.Debug("HUD restored")
end

--- Panic button: shows the HUD layer whether or not this mod thinks it hid it.
function HudUtils.ForceRestore(mod)
    SetHudVisible(true)
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
