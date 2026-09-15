-- ======================================================================================
-- Simple Time-lapse - Core Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Contains the "Business Logic": Time, Dilation, Audio, Messages, and Update Loop.
-- ======================================================================================

local CameraUtils = require("Modules/CameraUtils")
local Log = require("Modules/Log")
local VehicleDilation = require("Modules/VehicleDilation")
local Cron = require("Modules/Cron")
local Undo = require("Modules/Undo")
local TimingProbe = require("Modules/TimingProbe")
local GameTimeCurve = require("Modules/GameTimeCurve")
local Core = {}

-- Seconds between the HUD returning and the "Time-lapse Finished" message and sound,
-- which mark the end of the run on a recording.
local FINISH_MARKER_DELAY = 1.0

-- =================================================================
-- ### MESSAGES & AUDIO ###
-- =================================================================
--- Posts a message to one of the UI_Notifications blackboard fields.
local function PostScreenMessage(fieldName, text, duration)
    local msg = SimpleScreenMessage.new()
    msg.isShown = true; msg.duration = duration; msg.message = text
    local bbDefs = Game.GetAllBlackboardDefs()
    local bbNotify = Game.GetBlackboardSystem():Get(bbDefs.UI_Notifications)
    if bbNotify then bbNotify:SetVariant(bbDefs.UI_Notifications[fieldName], ToVariant(msg), true) end
end

function Core.Notify(mod, text)
    if not mod.settings.showMessages then return end
    PostScreenMessage("OnscreenMessage", text, 2.0)
end

--- Always shown, whatever the Messages setting, because it explains a refused action.
function Core.NotifyWarning(mod, text)
    PostScreenMessage("WarningMessage", text, 3.0)
    Core.PlaySound(mod, "ui_menu_deny")
end

function Core.PlaySound(mod, eventName)
    if not mod.settings.playAudio then return end
    local audio = Game.GetAudioSystem()
    if audio then audio:Play(CName.new(eventName)) end
end

-- =================================================================
-- ### GAME STATE CHECKS ###
-- =================================================================

function Core.IsCombatActive()
    local player = Game.GetPlayer()
    if not player then return false end
    -- Mirrors the player's state machine Combat value being InCombat.
    return player:IsInCombat()
end

-- =================================================================
-- ### TIME MATH ###
-- =================================================================

function Core.GetGameTimeStr()
    local ts = Game.GetTimeSystem(); if not ts then return "--:--" end
    local t = ts:GetGameTime()
    return string.format("%02d:%02d:%02d", t:Hours(), t:Minutes(), t:Seconds())
end

function Core.CalculateSecondsFromCombo(mod)
    local h = mod.settings.comboHour + 1; local m = mod.settings.comboMinute; local isPm = (mod.settings.comboAmPm == 1)
    local hour24 = h; if h == 12 then hour24 = isPm and 12 or 0 else hour24 = isPm and (h + 12) or h end
    return (hour24 * 3600) + (m * 60)
end

function Core.GetTotalGameSeconds()
    local ts = Game.GetTimeSystem(); if not ts then return 0 end
    local t = ts:GetGameTime()
    return (t:Days() * 86400) + (t:Hours() * 3600) + (t:Minutes() * 60) + t:Seconds()
end

function Core.FormatSecondsToTime(totalSeconds)
    totalSeconds = totalSeconds % 86400
    local h = math.floor(totalSeconds / 3600); local m = math.floor((totalSeconds % 3600) / 60); local s = math.floor(
        totalSeconds % 60)
    local suffix = "AM"; local h12 = h
    if h >= 12 then
        suffix = "PM"; if h > 12 then h12 = h - 12 end
    elseif h == 0 then
        h12 = 12
    end
    return string.format("%02d:%02d:%02d %s", h12, m, s, suffix)
end

function Core.FormatDuration(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then
        return string.format("%dh %dm %ds", h, m, s)
    elseif m > 0 then
        return string.format("%dm %ds", m, s)
    else
        return string.format("%ds", s)
    end
end

function Core.GetEstimatedData(mod)
    local startSecs = 0
    if mod.settings.useStartTime then
        startSecs = Core.CalculateSecondsFromCombo(mod)
    else
        local ts = Game.GetTimeSystem(); if ts then
            local t = ts:GetGameTime(); startSecs = (t:Hours() * 3600) + (t:Minutes() * 60) + t:Seconds()
        end
    end

    if mod.settings.duration <= 0 then
        return {
            endTime = "Infinite",
            totalSeconds = 0,
            startTimeStr = Core.FormatSecondsToTime(startSecs),
            durStr =
            "Infinite"
        }
    end

    local addedGameSeconds = 0
    if mod.settings.mode == 0 then
        -- Mode 0: Simulation (Dilation). Game time follows the vanilla hour-of-day curve.
        addedGameSeconds = GameTimeCurve.GameSecondsGained(startSecs, mod.settings.duration * Core.EffectiveDilation(mod))
    else
        -- Mode 1: Clock Only
        -- Speed = Game Seconds added per Real Second
        -- (Ignoring natural 8x passage as negligible/redundant for "Timelapse" intent)
        addedGameSeconds = mod.settings.duration * mod.settings.speed
    end

    return {
        endTime = Core.FormatSecondsToTime(startSecs + addedGameSeconds),
        totalSeconds = addedGameSeconds,
        startTimeStr = Core.FormatSecondsToTime(startSecs),
        durStr = Core.FormatDuration(addedGameSeconds)
    }
end

function Core.SetTimeNow(mod)
    local ts = Game.GetTimeSystem()
    if ts then
        ts:SetGameTimeBySeconds(Core.CalculateSecondsFromCombo(mod))
        Log.Debug("Time manually set")
        Core.PlaySound(mod, "ui_menu_click")
    end
end

-- =================================================================
-- ### START / STOP LOGIC ###
-- =================================================================

-- The engine runs the simulation at no more than 10x, whatever SetTimeDilation is given.
local ENGINE_MAX_DILATION = 10.0

--- Highest speed the current mode allows: Clock 10000x, Simulation the engine's 10x.
function Core.GetMaxSpeed(mod)
    if mod.settings.mode == 1 then return 10000.0 end
    return ENGINE_MAX_DILATION
end

--- The dilation a Simulation run actually gets.
function Core.EffectiveDilation(mod)
    return math.min(mod.settings.speed, ENGINE_MAX_DILATION)
end

function Core.ClampSpeed(mod)
    mod.settings.speed = math.max(0.0, math.min(mod.settings.speed, Core.GetMaxSpeed(mod)))
end

function Core.RecalcDuration(mod)
    local mult = 1.0
    if mod.ui.durationUnit == 1 then mult = 60.0 end
    if mod.ui.durationUnit == 2 then mult = 3600.0 end
    mod.settings.duration = mod.ui.durationVal * mult
end

function Core.ApplyDilation(val)
    local ts = Game.GetTimeSystem(); if not ts then return end
    local reason = CName.new("SimpleTimelapse")
    if val == 1.0 then
        ts:UnsetTimeDilation(reason)
    else
        ts:SetTimeDilation(reason, val)
    end
end

local AIR_TRAFFIC_FACT = "air_traffic_off"

function Core.CountReenabled(mod, name)
    local count = (mod.reenabled[name] or 0) + 1
    mod.reenabled[name] = count
    if count == 1 then
        Log.Debug("%s was switched back on mid-run at %s, re-applied", name, Core.GetGameTimeStr())
    end
end

function Core.DisableAirTraffic()
    local quests = Game.GetQuestsSystem()
    local before = quests:GetFactStr(AIR_TRAFFIC_FACT)
    if before == 1 then return end

    quests:SetFactStr(AIR_TRAFFIC_FACT, 1)
    Undo.Push("airTraffic", function()
        local q = Game.GetQuestsSystem()
        if q and q:GetFactStr(AIR_TRAFFIC_FACT) == 1 then q:SetFactStr(AIR_TRAFFIC_FACT, before) end
    end)
end

function Core.DisableCrowds()
    if GameOptions.GetBool("Crowd", "Enabled") == false then return end

    GameOptions.SetBool("Crowd", "Enabled", false)
    Undo.Push("crowds", function()
        if GameOptions.GetBool("Crowd", "Enabled") == false then GameOptions.SetBool("Crowd", "Enabled", true) end
    end)
end

function Core.ExecuteStart(mod, HudUtils)
    -- IMPORTANT: Set delaying to false immediately to prevent update loops if subsequent code crashes
    mod.isDelaying = false

    Core.RecalcDuration(mod)
    if mod.settings.useStartTime then
        local timeBefore = Core.GetTotalGameSeconds()
        Core.SetTimeNow(mod)
        if mod.settings.restoreTime then
            Undo.Push("time", function()
                local ts = Game.GetTimeSystem()
                if ts then ts:SetGameTimeBySeconds(timeBefore) end
            end)
        end
    end

    mod.startGameTime = Core.GetTotalGameSeconds()
    local startStr = Core.FormatSecondsToTime(mod.startGameTime)

    Log.Info("Started: %s mode, %.1fx, start %s, duration %.2fs, est. end %s",
        mod.settings.mode == 0 and "Simulation" or "Clock", mod.settings.speed, startStr,
        mod.settings.duration, Core.GetEstimatedData(mod).endTime)
    Core.PlaySound(mod, "ui_menu_click")

    -- Every change below records its own undo, so Stop puts back only what this run changed.
    -- A HUD the player already hid is left to them, and Stop does not show it.
    if mod.settings.autoHideHud and not mod.hudHidden then
        HudUtils.Hide(mod)
        if mod.hudHidden then
            mod.runHidHud = true
            Undo.Push("hud", function()
                if mod.runHidHud then
                    HudUtils.Restore(mod)
                    mod.runHidHud = false
                end
            end)
        end
    end

    if mod.settings.disableHeadBob then
        CameraUtils.Disable()
    end

    CameraUtils.LockPlayer(mod)

    if mod.settings.disableAirTraffic then
        Core.DisableAirTraffic()
    end

    if mod.settings.disableCrowds then
        Core.DisableCrowds()
    end

    if mod.settings.mode == 0 then
        -- Mode 0: Simulation Speed (Time Dilation)
        Core.ApplyDilation(mod.settings.speed)
        Undo.Push("dilation", function() Core.ApplyDilation(1.0) end)
    else
        -- Mode 1: Clock Speed (Manual Advancement)
        mod.clockAccumulator = 0.0
        mod.totalGameTimeAdded = 0.0
        mod.startTotalSeconds = Core.GetTotalGameSeconds()
        -- Ensure dilation is 1.0 so physics don't break
        Core.ApplyDilation(1.0)
    end

    TimingProbe.Start()
    mod.reenabled = {}
    mod.elapsedTime = 0
    mod.isActive = true
    mod.lastRunStats.valid = false
    mod.overlayMessage = nil

    if mod.settings.forceVehicleDilation and mod.settings.mode == 0 then
        VehicleDilation.Start(mod.settings.frenzySpeedMult)
        Log.Info("Traffic Frenzy active at %.1fx", mod.settings.frenzySpeedMult)
    end
end

--- Stops a run or cancels its countdown when the game pauses: the pause menu, any hub menu,
--- photo mode or a tutorial popup. The CET overlay does not pause the game.
function Core.OnGamePaused(mod, HudUtils)
    if not mod.isActive and not mod.isDelaying then return end
    Log.Info("A menu opened, stopping")
    mod.stoppedByMenu = true
    Core.Stop(mod, HudUtils)
end

--- Tells the player why the run ended, once the menu that stopped it has closed.
function Core.OnGameResumed(mod)
    if not mod.stoppedByMenu then return end
    mod.stoppedByMenu = false
    Core.Notify(mod, "Time-lapse stopped: a menu was opened")
end

function Core.Stop(mod, HudUtils)
    local wasActive = mod.isActive
    mod.isActive = false
    mod.isDelaying = false
    mod.overlayMessage = nil

    -- Read before the undo list runs, because Restore Time moves the clock.
    local actualEndSeconds = Core.GetTotalGameSeconds()

    if wasActive and mod.reenabled then
        Log.Debug("Switched back on mid-run: crowds %d frames, air traffic %d frames",
            mod.reenabled.crowds or 0, mod.reenabled.airTraffic or 0)
    end

    Undo.RunAll()

    if wasActive and mod.elapsedTime > 0 then
        -- A run a menu stopped gets the menu message on resume instead of the finish marker.
        if not mod.stoppedByMenu then
            mod.finishMarkerTimer = Cron.After(FINISH_MARKER_DELAY, function()
                mod.finishMarkerTimer = nil
                Core.Notify(mod, "Time-lapse Finished")
                Core.PlaySound(mod, "ui_hacking_access_granted")
            end)
        end

        -- Calculate the run stats.
        local gameSecondsPassed = actualEndSeconds - mod.startGameTime

        -- Simulation: game time gained against the vanilla curve's prediction.
        -- Clock: game time gained against speed times real time.
        local expected
        if mod.settings.mode == 0 then
            expected = GameTimeCurve.GameSecondsGained(mod.startGameTime, mod.elapsedTime * Core.EffectiveDilation(mod))
        else
            expected = mod.elapsedTime * mod.settings.speed
        end
        local factor = 0
        if expected > 0 then factor = gameSecondsPassed / expected end

        mod.lastRunStats.mode = mod.settings.mode
        mod.lastRunStats.speedSetting = mod.settings.speed
        mod.lastRunStats.durationReal = mod.elapsedTime
        mod.lastRunStats.timePassedGame = gameSecondsPassed
        mod.lastRunStats.timeExpectedGame = expected
        mod.lastRunStats.factor = factor
        mod.lastRunStats.valid = true

        Log.Info("Stopped: %.2f game seconds in %.2f real seconds, expected %.2f, %s %.1f%%",
            gameSecondsPassed, mod.elapsedTime, expected,
            mod.settings.mode == 0 and "curve match" or "clock efficiency", factor * 100)
    end
end

--- Puts back everything the run changed, plus a HUD the player hid by hand, with no
--- finish marker or run stats. For session end and shutdown.
function Core.Cleanup(mod, HudUtils)
    mod.stoppedByMenu = false
    mod.isActive = false
    mod.isDelaying = false
    mod.overlayMessage = nil
    if mod.finishMarkerTimer then
        Cron.Halt(mod.finishMarkerTimer)
        mod.finishMarkerTimer = nil
    end

    Undo.RunAll()
    if mod.hudHidden then HudUtils.Restore(mod) end
end

function Core.Start(mod, HudUtils)
    if mod.isActive or mod.isDelaying then return end

    if mod.finishMarkerTimer then
        Cron.Halt(mod.finishMarkerTimer)
        mod.finishMarkerTimer = nil
    end

    if mod.settings.blockInCombat and Core.IsCombatActive() then
        Core.NotifyWarning(mod, "Cannot start Time-lapse during Combat!")
        Log.Info("Start refused: player is in combat")
        return
    end

    if mod.settings.startDelay > 0 then
        mod.delayTimer = mod.settings.startDelay
        mod.isDelaying = true
        mod.lastCountdownInt = math.ceil(mod.delayTimer)
        Log.Debug("Countdown: %.1fs", mod.settings.startDelay)
        if mod.lastCountdownInt > 1 then
            Core.Notify(mod, "Starting in " .. mod.lastCountdownInt .. "...")
            Core.PlaySound(mod, "ui_menu_hover")
        end
    else
        Core.ExecuteStart(mod, HudUtils)
    end
end

local lastSimTime = nil

--- Simulation seconds since the previous frame. Zero while the game is paused.
local function SimStep()
    local ts = Game.GetTimeSystem()
    if not ts then return 0 end
    local now = EngineTime.ToDouble(ts:GetSimTime())
    local step = lastSimTime and math.max(now - lastSimTime, 0) or 0
    lastSimTime = now
    return step
end

function Core.Update(mod, delta, HudUtils)
    -- The countdown and the run count simulated seconds, converted back to real seconds at the
    -- run's dilation, so time spent paused never counts towards them.
    local simStep = SimStep()

    if mod.isDelaying then
        mod.delayTimer = mod.delayTimer - simStep

        local currentInt = math.ceil(mod.delayTimer)
        if currentInt ~= mod.lastCountdownInt then
            if currentInt > 1 then
                Core.Notify(mod, "Starting in " .. currentInt .. "...")
                Core.PlaySound(mod, "ui_menu_hover")
            end
            mod.lastCountdownInt = currentInt
        end

        if mod.delayTimer <= 0 then
            Core.ExecuteStart(mod, HudUtils)
        end
    elseif mod.isActive then
        local runStep = simStep
        if mod.settings.mode == 0 then
            local dilation = Core.EffectiveDilation(mod)
            -- At 0x the simulation never moves, so a paused shot counts real time instead.
            if dilation > 0 then runStep = simStep / dilation else runStep = delta end
        end
        mod.elapsedTime = mod.elapsedTime + runStep
        if mod.settings.mode == 0 then TimingProbe.Update(delta, mod.settings.speed) end

        -- MODE 1: CLOCK ADVANCEMENT
        if mod.settings.mode == 1 then
            -- Integrate time strictly (step * Speed)
            -- This avoids "read-back lag" from GetGameTime() and ensures 100% efficiency.
            local step = runStep * mod.settings.speed
            mod.totalGameTimeAdded = mod.totalGameTimeAdded + step

            local ts = Game.GetTimeSystem()
            if ts then
                local targetTime = mod.startTotalSeconds + mod.totalGameTimeAdded
                ts:SetGameTimeBySeconds(math.floor(targetTime))
            end
        end

        if mod.settings.duration > 0 then
            if mod.elapsedTime >= mod.settings.duration then
                Log.Info("Duration reached, stopping")
                Core.Stop(mod, HudUtils)
            end
        end

        -- Re-applied every frame, and only when this run made the change, so a box ticked
        -- mid-run never writes a value that Stop has no snapshot for.
        -- Each re-apply that found the value switched back is counted and reported at Stop.
        if Undo.Has("crowds") then
            if GameOptions.GetBool("Crowd", "Enabled") ~= false then
                Core.CountReenabled(mod, "crowds")
                GameOptions.SetBool("Crowd", "Enabled", false)
            end
        end
        if Undo.Has("airTraffic") then
            local quests = Game.GetQuestsSystem()
            if quests:GetFactStr(AIR_TRAFFIC_FACT) ~= 1 then
                Core.CountReenabled(mod, "airTraffic")
                quests:SetFactStr(AIR_TRAFFIC_FACT, 1)
            end
        end
        if VehicleDilation.IsRunning() then
            VehicleDilation.Update(delta, mod.settings.frenzySpeedMult)
        end
    end
end

return Core
