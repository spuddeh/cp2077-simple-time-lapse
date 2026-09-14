-- ======================================================================================
-- Simple Time-lapse - Core Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Contains the "Business Logic": Time, Dilation, Audio, Messages, and Update Loop.
-- ======================================================================================

local GameSettings = require("Modules/GameSettings")
local CameraUtils = require("Modules/CameraUtils")
local VehicleDilation = require("Modules/VehicleDilation")
local Core = {}

-- =================================================================
-- ### LOGGING & AUDIO ###
-- =================================================================

function Core.Log(mod, msg)
    print(msg)
    if mod.settings.logToFile then spdlog.info(msg) end
end

function Core.Notify(mod, text)
    if not mod.settings.showMessages then return end
    local msg = SimpleScreenMessage.new()
    msg.isShown = true; msg.duration = 2.0; msg.message = text
    local bbDefs = Game.GetAllBlackboardDefs()
    local bbNotify = Game.GetBlackboardSystem():Get(bbDefs.UI_Notifications)
    if bbNotify then bbNotify:SetVariant(bbDefs.UI_Notifications.OnscreenMessage, ToVariant(msg), true) end
end

function Core.NotifyWarning(mod, text)
    local msg = SimpleScreenMessage.new()
    msg.isShown = true; msg.duration = 3.0; msg.message = text
    local bbDefs = Game.GetAllBlackboardDefs()
    local bbNotify = Game.GetBlackboardSystem():Get(bbDefs.UI_Notifications)
    if bbNotify then bbNotify:SetVariant(bbDefs.UI_Notifications.WarningMessage, ToVariant(msg), true) end
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

    local bb = nil
    if player['GetPlayerStateMachineBlackboard'] then
        bb = player:GetPlayerStateMachineBlackboard()
    end
    if not bb then
        local bbDefs = Game.GetAllBlackboardDefs()
        bb = Game.GetBlackboardSystem():Get(bbDefs.PlayerStateMachine)
    end
    if bb then
        local bbDefs = Game.GetAllBlackboardDefs()
        local combatState = bb:GetInt(bbDefs.PlayerStateMachine.Combat)
        return combatState == 1 -- 1 = InCombat
    end
    return false
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
        -- Mode 0: Simulation (Dilation)
        -- 1x Dilation = Normal Game Speed (~8 Game Seconds per Real Second)
        local limit = 10.0
        if mod.settings.unlockSpeed then limit = 100.0 end
        local effectiveSpeed = math.min(mod.settings.speed, limit)
        addedGameSeconds = mod.settings.duration * effectiveSpeed * 8.0
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
        print("[Time-lapse] Time manually set")
        Core.PlaySound(mod, "ui_menu_click")
    end
end

-- =================================================================
-- ### START / STOP LOGIC ###
-- =================================================================

--- Highest speed the current mode allows: Clock 10000x, Simulation 10x, or 100x unlocked.
function Core.GetMaxSpeed(mod)
    if mod.settings.mode == 1 then return 10000.0 end
    if mod.settings.unlockSpeed then return 100.0 end
    return 10.0
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

function Core.ExecuteStart(mod, HudUtils)
    -- IMPORTANT: Set delaying to false immediately to prevent update loops if subsequent code crashes
    mod.isDelaying = false

    Core.RecalcDuration(mod)
    if mod.settings.useStartTime then Core.SetTimeNow(mod) end

    mod.startGameTime = Core.GetTotalGameSeconds()
    local startStr = Core.FormatSecondsToTime(mod.startGameTime)

    print("[Time-lapse] STARTING... (" .. mod.settings.speed .. "x)")
    Core.PlaySound(mod, "ui_menu_click")

    if mod.settings.logToFile then
        local data = Core.GetEstimatedData(mod)
        spdlog.info("=== TIME-LAPSE START ===")
        spdlog.info(string.format("Start Time:   %s", startStr))
        spdlog.info(string.format("Duration:     %.2fs", mod.settings.duration))
        spdlog.info(string.format("Speed:        %.1fx", mod.settings.speed))
        spdlog.info(string.format("Est. End:     %s", data.endTime))
        spdlog.info("=======================")
    end

    if mod.settings.autoHideHud and not mod.hudHidden then
        HudUtils.Hide(mod)
    end

    if mod.settings.disableHeadBob then
        CameraUtils.Disable(mod)
    end

    CameraUtils.LockPlayer(mod) -- Lock Controls

    if mod.settings.disableAirTraffic then
        Game.GetQuestsSystem():SetFactStr("air_traffic_off", 1)
    end

    if mod.settings.disableCrowds then
        GameOptions.SetBool("Crowd", "Enabled", false)
    end

    if mod.settings.mode == 0 then
        -- Mode 0: Simulation Speed (Time Dilation)
        Core.ApplyDilation(mod.settings.speed)
    else
        -- Mode 1: Clock Speed (Manual Advancement)
        mod.clockAccumulator = 0.0
        mod.totalGameTimeAdded = 0.0
        mod.startTotalSeconds = Core.GetTotalGameSeconds()
        -- Ensure dilation is 1.0 so physics don't break
        Core.ApplyDilation(1.0)
    end

    mod.elapsedTime = 0
    mod.isActive = true
    mod.lastRunStats.valid = false
    mod.overlayMessage = nil

    if mod.settings.forceVehicleDilation and mod.settings.mode == 0 then
        if VehicleDilation then VehicleDilation.Start(mod.settings.frenzySpeedMult) end
        Core.Log(mod, "[Time-lapse] Traffic Speed Override Active.")
    end
end

function Core.Stop(mod, HudUtils)
    local wasActive = mod.isActive
    mod.isActive = false
    mod.isDelaying = false
    mod.overlayMessage = nil

    -- Always reset dilation, safe for both modes
    Core.ApplyDilation(1.0)

    if VehicleDilation then VehicleDilation.Stop() end

    if mod.settings.autoHideHud and mod.hudHidden then
        HudUtils.Restore(mod)
    end

    CameraUtils.Restore(mod)
    CameraUtils.UnlockPlayer(mod) -- Unlock Controls

    Game.GetQuestsSystem():SetFactStr("air_traffic_off", 0)
    GameOptions.SetBool("Crowd", "Enabled", true)

    if wasActive and mod.elapsedTime > 0 then
        Core.Notify(mod, "Time-lapse Finished")
        Core.PlaySound(mod, "ui_hacking_access_granted")

        local actualEndSeconds = Core.GetTotalGameSeconds()
        local actualEndStr = Core.FormatSecondsToTime(actualEndSeconds)

        -- Calculate the run stats.
        local gameSecondsPassed = actualEndSeconds - mod.startGameTime
        local factor = 0
        local ratio = 0
        if mod.elapsedTime > 0 then ratio = gameSecondsPassed / mod.elapsedTime end

        if mod.settings.speed > 0 then
            factor = ratio / mod.settings.speed
        end

        mod.lastRunStats.speedSetting = mod.settings.speed
        mod.lastRunStats.durationReal = mod.elapsedTime
        mod.lastRunStats.timePassedGame = gameSecondsPassed
        mod.lastRunStats.factor = factor
        mod.lastRunStats.valid = true

        print("[Time-lapse] STOPPED.")

        if mod.settings.logToFile then
            spdlog.info("=== TIME-LAPSE STOP ===")
            spdlog.info(string.format("Mode: %s", (mod.settings.mode == 0 and "Simulation" or "Clock")))
            spdlog.info(string.format("Stats: %.2f GameSecs in %.2f RealSecs", gameSecondsPassed, mod.elapsedTime))
            if mod.settings.mode == 0 then
                spdlog.info(string.format("Calibration Factor: %.4f", factor))
            else
                spdlog.info(string.format("Clock Efficiency: %.4f", factor))
            end
            spdlog.info("======================")
        end
    end
end

function Core.Start(mod, HudUtils)
    if mod.isActive or mod.isDelaying then return end

    if Core.IsCombatActive() then
        Core.NotifyWarning(mod, "Cannot start Time-lapse during Combat!")
        print("[Time-lapse] Start blocked: In Combat.")
        return
    end

    if mod.settings.startDelay > 0 then
        mod.delayTimer = mod.settings.startDelay
        mod.isDelaying = true
        mod.lastCountdownInt = math.ceil(mod.delayTimer)
        print(string.format("[Time-lapse] Countdown: %.1fs...", mod.settings.startDelay))
        if mod.lastCountdownInt > 1 then
            Core.Notify(mod, "Starting in " .. mod.lastCountdownInt .. "...")
            Core.PlaySound(mod, "ui_menu_hover")
        end
    else
        Core.ExecuteStart(mod, HudUtils)
    end
end

function Core.Update(mod, delta, HudUtils)
    if mod.isDelaying then
        mod.delayTimer = mod.delayTimer - delta

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
        mod.elapsedTime = mod.elapsedTime + delta

        -- MODE 1: CLOCK ADVANCEMENT
        if mod.settings.mode == 1 then
            -- Integrate time strictly (RealDelta * Speed)
            -- This avoids "read-back lag" from GetGameTime() and ensures 100% efficiency.
            local step = delta * mod.settings.speed
            mod.totalGameTimeAdded = mod.totalGameTimeAdded + step

            local ts = Game.GetTimeSystem()
            if ts then
                local targetTime = mod.startTotalSeconds + mod.totalGameTimeAdded
                ts:SetGameTimeBySeconds(math.floor(targetTime))
            end
        end

        if mod.settings.duration > 0 then
            if mod.elapsedTime >= mod.settings.duration then
                Core.Log(mod, "[Time-lapse] Duration reached. Stopping.")
                Core.Stop(mod, HudUtils)
            end
        end

        -- Ensure toggles are aggressively applied during the timelapse
        if mod.settings.disableCrowds then
            GameOptions.SetBool("Crowd", "Enabled", false)
        end
        if mod.settings.disableAirTraffic then
            Game.GetQuestsSystem():SetFactStr("air_traffic_off", 1)
        end
        if mod.settings.forceVehicleDilation and mod.settings.mode == 0 and VehicleDilation then
            VehicleDilation.Update(delta, mod.settings.frenzySpeedMult)
        end
    end
end

return Core
