-- ======================================================================================
-- Simple Time-lapse - HudUtils Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Hides and restores the HUD by hiding the Root canvas of the HUD layer, reached through
-- Codeware's inkSystem. Every game HUD widget draws inside Root, notifications, the
-- vehicle HUD and the scanner included, and the game never sets its visibility, so it
-- stays hidden whatever context the game pushes. No user setting and no UI context
-- changes.
--
-- Root, not the layer window: other mods parent overlays onto the window beside Root,
-- XUtils' cinematic bars among them, and those stay on screen.
--
-- Root is resolved on every call rather than cached, because a new session builds a new
-- layer. Without Codeware there is no layer to reach and the HUD is left alone.
-- ======================================================================================

local Log = require("Modules/Log")
local HudUtils = {}

local warnedMissing = false

--- The HUD layer's Root canvas, or nil when Codeware is missing or no session is running.
local function HudRoot()
    local ok, root = pcall(function()
        local window = Game.GetInkSystem():GetLayer(CName.new("inkHUDLayer")):GetVirtualWindow()
        for i = 0, window:GetNumChildren() - 1 do
            local child = window:GetWidget(i)
            if child:GetName().value == "Root" then return child end
        end
        return nil
    end)
    if ok and root then return root end
    return nil
end

--- True when Codeware is installed, so the HUD can be hidden at all.
function HudUtils.IsAvailable()
    local ok, inkSystem = pcall(function() return Game.GetInkSystem() end)
    return ok and inkSystem ~= nil
end

local function SetHudVisible(visible)
    local root = HudRoot()
    if not root then
        if not warnedMissing then
            Log.Warn("The HUD layer is out of reach, so the HUD is left alone. Hiding it needs Codeware")
            warnedMissing = true
        end
        return false
    end
    root:SetVisible(visible)
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

--- Panic button: shows the HUD whether or not this mod thinks it hid it.
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
