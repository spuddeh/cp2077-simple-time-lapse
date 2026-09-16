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
-- The vehicle HUD is not one of them. Its widgets list VehicleMounted as a context they
-- are visible in, and neither a second Empty over that context nor a forced entry
-- visibility moves them, so each vehicle HUD controller is caught as it initialises and
-- its root widget is hidden directly - which is what the game's own HideRequest does.
--
-- The scanner pushes its own context and is left alone: a scanner that cannot be read is
-- worse than a scanner on screen.
-- ======================================================================================

local Log = require("Modules/Log")
local Cron = require("Modules/Cron")
local HudUtils = {}

local function EmptyContext()
    return Enum.new("UIGameContext", "Empty")
end

-- Every vehicle HUD controller seen this session. Weak keys, so a controller the game
-- has thrown away does not stay alive here.
local vehicleControllers = setmetatable({}, { __mode = "k" })

--- Shows or hides the root widget of every vehicle HUD controller still alive.
local function SetVehicleHudVisible(visible)
    local count = 0
    for controller in pairs(vehicleControllers) do
        local ok = pcall(function()
            local root = controller:GetRootWidget()
            if root then
                root:SetVisible(visible)
                count = count + 1
            end
        end)
        if not ok then vehicleControllers[controller] = nil end
    end
    Log.Debug("Vehicle HUD set %s on %d controller(s)", visible and "visible" or "hidden", count)
end

--- Catches each vehicle HUD as it initialises. Registered once, because an observer
--- cannot be taken off again.
function HudUtils.Init(mod)
    local function Track(self)
        vehicleControllers[self] = true
        if not mod.hudHidden then return end
        -- The widget tree is not always ready in the same frame the controller is.
        SetVehicleHudVisible(false)
        Cron.After(0.2, function()
            if mod.hudHidden then SetVehicleHudVisible(false) end
        end)
    end

    Observe("hudCarController", "OnInitialize", Track)
    Observe("inkMotorcycleHUDGameController", "OnInitialize", Track)
end

function HudUtils.Hide(mod)
    if mod.hudHidden then return end
    local uiSystem = Game.GetUISystem()
    if not uiSystem then return end

    uiSystem:PushGameContext(EmptyContext())
    mod.hudHidden = true
    SetVehicleHudVisible(false)
    Log.Debug("HUD hidden")
end

function HudUtils.Restore(mod)
    if not mod.hudHidden then return end
    local uiSystem = Game.GetUISystem()
    if not uiSystem then return end

    uiSystem:PopGameContext(EmptyContext())
    mod.hudHidden = false
    SetVehicleHudVisible(true)
    Log.Debug("HUD restored")
end

--- Panic button: pops the Empty context whether or not this mod thinks it pushed one,
--- and puts every vehicle HUD back on screen.
function HudUtils.ForceRestore(mod)
    local uiSystem = Game.GetUISystem()
    if uiSystem then uiSystem:PopGameContext(EmptyContext()) end
    mod.hudHidden = false
    SetVehicleHudVisible(true)
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
