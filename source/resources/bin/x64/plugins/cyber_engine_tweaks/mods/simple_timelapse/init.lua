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
local Settings = require("Modules/Settings")
local Log = require("Modules/Log")
local Cron = require("Modules/Cron")
local GameSession = require("Modules/GameSession")
local Notifications = require("Modules/Notifications")
local Presets = require("Modules/Presets")

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
    runHidHud = false, -- true while the current run is the one that hid the HUD

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
        clockUnit = 0,
        unitLabels = { "Seconds", "Minutes", "Hours" }
    },

    settings = {
        mode = 0, -- 0: Simulation (Dilation), 1: Clock Only
        speed = 5.0,
        duration = 10.0,
        runUntilStopped = false,
        useStartTime = false,
        restoreTime = false,
        startDelay = 3.0,
        autoHideHud = true,
        disableHeadBob = true,
        lockMovement = true,
        lockCamera = true,
        lockWeapons = true,
        showMessages = true,
        playAudio = true,
        disableAirTraffic = false,
        disableCrowds = false,
        blockInCombat = true,
        muteRadio = true,
        muteMusic = false,
        muteSfx = false,
        muteNotifications = true,

        -- XUtils features, skipped when XUtils is not installed.
        xuLens = false,
        xuDofMode = 2,
        xuFocalLength = 35.0,
        xuFstop = 8.0,
        xuDofIntensity = 1.0,
        xuZoomWithLens = false,
        xuAutofocus = true,
        xuFocusDist = 10.0,
        xuFocusRange = 200.0,
        xuFocusSpeed = 0.4,
        xuFocusCurve = 0,
        xuWeather = false,
        xuWeatherMode = 0,
        xuWeatherBlend = 10.0,
        xuWeatherList = {},
        xuBars = false,
        xuBarsRatio = 0,
        xuFadeIn = false,
        xuFadeInTime = 2.0,
        xuFadeOut = false,
        xuFadeOutTime = 2.0,

        logLevel = Log.DEFAULT_LEVEL,
        forceVehicleDilation = false, -- Experimental
        frenzySpeedMult = 1.5,
        -- Seconds since midnight. 6 AM.
        startSeconds = 21600.0,

        -- Auto speed: Clock mode works its speed out from the start and end times and the
        -- run's length.
        clockAuto = false,
        endSeconds = 64800.0,
        autoAcrossDays = false,
        autoDays = 1,
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
    Notifications.Init(mod)
    Presets.Load()
    Log.SetLevel(mod.settings.logLevel)
    -- Loading a save or quitting to the menu ends the session without a Stop.
    GameSession.OnEnd(function() Core.Cleanup(mod, HudUtils) end)
    GameSession.OnPause(function() Core.OnGamePaused(mod, HudUtils) end)
    GameSession.OnResume(function() Core.OnGameResumed(mod) end)
    Log.Info("Initialized (%s)", mod.version)
end)

registerForEvent("onShutdown", function()
    Settings.Save(mod)
    Core.Cleanup(mod, HudUtils)
end)

registerForEvent("onOverlayOpen", function() mod.isOverlayOpen = true end)
registerForEvent("onOverlayClose", function()
    mod.isOverlayOpen = false
    Settings.Save(mod)
end)
-- Pass CameraUtils to UI so debug buttons and Start/Stop work
registerForEvent("onDraw", function() UI.Draw(mod, Core, HudUtils, CameraUtils) end)

registerForEvent("onUpdate", function(delta)
    Cron.Update(delta)
    Core.Update(mod, delta, HudUtils)
end)

return mod
