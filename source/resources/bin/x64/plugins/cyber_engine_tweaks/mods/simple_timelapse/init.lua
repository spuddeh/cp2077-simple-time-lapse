-- ======================================================================================
-- Simple Time-lapse - Init Module
-- Mod Version:  v1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Entry point. Manages global state, settings, event registration, and module loading.
-- ======================================================================================

local Core = require("Modules/Core")
local UI = require("Modules/UI")
local HudUtils = require("Modules/HudUtils")
local CameraUtils = require("Modules/CameraUtils")
local VehicleDilation = require("Modules/VehicleDilation")
local Settings = require("Modules/Settings")
local Log = require("Modules/Log")

local mod = {
    version = "v1.3.0",
    isOverlayOpen = false,
    isActive = false,

    -- Delay State
    isDelaying = false,
    delayTimer = 0,
    lastCountdownInt = 0,

    -- HUD State
    hudHidden = false,

    -- Camera State
    cameraPath = nil,
    cameraSnapshot = nil,

    -- Debug/Stats
    startGameTime = 0,
    lastRunStats = { valid = false, speedSetting = 0, durationReal = 0, timePassedGame = 0, factor = 0 },

    -- Clock Mode State
    clockAccumulator = 0.0,
    totalGameTimeAdded = 0.0,
    startTotalSeconds = 0.0,

    ui = {
        durationVal = 10.0,
        durationUnit = 0,
        unitLabels = { "Seconds", "Minutes", "Hours" }
    },

    settings = {
        mode = 0, -- 0: Simulation (Dilation), 1: Clock Only
        speed = 5.0,
        duration = 10.0,
        useStartTime = false,
        startDelay = 3.0,
        autoHideHud = true,
        disableHeadBob = true,
        lockMovement = true,
        lockCamera = true,
        showMessages = true,
        playAudio = true,
        disableAirTraffic = false,
        disableCrowds = false,

        unlockSpeed = false,
        logLevel = Log.DEFAULT_LEVEL,
        forceVehicleDilation = false, -- Experimental
        frenzySpeedMult = 1.5,
        comboHour = 5,
        comboMinute = 0,
        comboAmPm = 0
    }
}

Settings.Init(mod)

-- =================================================================
-- ### REGISTRATION ###
-- =================================================================

registerHotkey("ToggleTimelapse", "Start/Stop Time-lapse", function()
    if mod.isActive then
        Core.Stop(mod, HudUtils)
    else
        Core.Start(mod, HudUtils)
    end
end)

registerHotkey("ToggleHUD", "Toggle HUD", function()
    HudUtils.Toggle(mod)
end)

registerForEvent("onInit", function()
    Settings.Load(mod, Core)
    Log.SetLevel(mod.settings.logLevel)
    Log.Info("Initialized (%s)", mod.version)
end)

registerForEvent("onShutdown", function()
    Settings.Save(mod)
    if mod.hudHidden then
        HudUtils.Restore(mod)
    end
    CameraUtils.Restore(mod)
    CameraUtils.UnlockPlayer(mod)
end)

registerForEvent("onOverlayOpen", function() mod.isOverlayOpen = true end)
registerForEvent("onOverlayClose", function()
    mod.isOverlayOpen = false
    Settings.Save(mod)
end)
-- Pass CameraUtils to UI so debug buttons and Start/Stop work
registerForEvent("onDraw", function() UI.Draw(mod, Core, HudUtils, CameraUtils) end)

registerForEvent("onUpdate", function(delta)
    Core.Update(mod, delta, HudUtils)
end)

return mod
