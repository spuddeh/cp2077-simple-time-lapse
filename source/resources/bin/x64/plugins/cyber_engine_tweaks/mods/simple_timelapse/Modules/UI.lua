-- ======================================================================================
-- Simple Time-lapse - UI Module
-- Mod Version:  v1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- The whole window, drawn with Window Utils, a required dependency. Controls, colours
-- and spacing come from the library rather than raw ImGui wherever it offers them.
-- Layout: the status line and preset row pinned at the top, a tab bar, the tab's own
-- scrolling body, and the clock readout with START pinned at the bottom.
-- ======================================================================================

local Log = require("Modules/Log")
local Settings = require("Modules/Settings")
local AudioUtils = require("Modules/AudioUtils")
local Notifications = require("Modules/Notifications")
local Presets = require("Modules/Presets")

local UI = {}

local WINDOW_NAME = "Simple Time-lapse"

-- Choices for the Start Time combos. Index 0 is 1 o'clock and 00 minutes.
local HOURS = {}; for i = 1, 12 do HOURS[i] = tostring(i) end
local MINUTES = {}; for i = 0, 59 do MINUTES[i + 1] = string.format("%02d", i) end

local wu = nil
local binding = nil

-- Height of the pinned footer, measured each frame and used to size the body on the next.
local footerHeight = 120

-- Preset row state. The name box is only on screen while a save is being named.
local presetIndex = 0
local naming = false
local nameInput = ""

--- Shown in place of the window when Window Utils is not installed.
local function DrawMissingDependency()
    if ImGui.Begin(WINDOW_NAME, ImGuiWindowFlags.AlwaysAutoResize) then
        ImGui.TextColored(1, 0.3, 0.3, 1, "Simple Time-lapse requires Window Utils.")
        ImGui.Text("Install it from Nexus Mods (mod 26589). The hotkeys still work without it.")
    end
    ImGui.End()
end

--- The scrolling area of a tab, sized so the footer always stays on screen.
local function TabBody(id, contentFn)
    if wu.Controls.BeginFillChild(id, { footerHeight = footerHeight, border = true }) then
        contentFn()
    end
    wu.Controls.EndFillChild(id)
end

-- =================================================================
-- ### PRESETS ###
-- =================================================================

local function SelectedPresetName()
    return Presets.Names()[presetIndex + 1]
end

local function DrawPresetRow(mod, Core, spacing)
    local names = Presets.Names()
    if presetIndex > #names - 1 then presetIndex = math.max(#names - 1, 0) end

    local selected = SelectedPresetName()
    local availW = ImGui.GetContentRegionAvail()
    local buttonW = 76
    local comboW = availW - (buttonW + spacing) * 2

    ImGui.BeginDisabled(mod.isActive)
    ImGui.SetNextItemWidth(comboW)
    local newIndex, changed = wu.Controls.Combo(IconGlyphs.FolderStarOutline, "Preset", presetIndex, names, {
        tooltip = "Loads a saved set of options.\nA preset carries every setting except the log level and Traffic Frenzy.",
    })
    if changed then
        presetIndex = newIndex
        local name = SelectedPresetName()
        if name then
            Presets.Apply(mod, name, Core)
            Settings.Save(mod)
            Core.PlaySound(mod, "ui_menu_click")
        end
    end
    ImGui.EndDisabled()

    ImGui.SameLine()
    wu.Controls.ButtonRow({
        {
            label = "Save",
            width = buttonW,
            disabled = mod.isActive and "hard" or nil,
            tooltip = "Saves the current options under a name you type.\nAn existing name is replaced.",
            onClick = function()
                naming = true
                nameInput = selected or ""
            end,
        },
        {
            label = "Delete",
            type = "hold",
            width = buttonW,
            style = "danger",
            disabled = (mod.isActive or selected == nil or Presets.IsBuiltin(selected)) and "hard" or nil,
            holdDuration = 1.0,
            progressDisplay = "overlay",
            tooltip = "Hold to delete the selected preset. The presets that ship with the mod stay.",
            onHold = function()
                if selected and Presets.Delete(selected) then
                    presetIndex = 0
                    Core.PlaySound(mod, "ui_menu_click")
                end
            end,
        },
    })

    if naming then
        ImGui.SetNextItemWidth(comboW)
        local text = wu.Controls.InputText(IconGlyphs.RenameBox, "PresetName", nameInput, { maxLength = 64 })
        nameInput = text

        ImGui.SameLine()
        wu.Controls.ButtonRow({
            {
                label = "Confirm",
                width = buttonW,
                style = "active",
                disabled = (nameInput == "") and "hard" or nil,
                onClick = function()
                    if Presets.Save(mod, nameInput) then
                        for i, name in ipairs(Presets.Names()) do
                            if name == nameInput then presetIndex = i - 1 end
                        end
                        naming = false
                        Core.PlaySound(mod, "ui_menu_click")
                    end
                end,
            },
            {
                label = "Cancel",
                width = buttonW,
                onClick = function() naming = false end,
            },
        })
    end
end

-- =================================================================
-- ### TABS ###
-- =================================================================

local function DrawShotTab(mod, Core, c, spacing)
    local bodyW = ImGui.GetContentRegionAvail()
    local runLocked = mod.isActive

    if runLocked then
        wu.Controls.TextMuted("Mode and speed are locked while a time-lapse runs.")
    end

    wu.Controls.SectionHeader("Mode", nil, 4, nil, nil, { separatorAfter = true })
    ImGui.BeginDisabled(runLocked)
    if ImGui.RadioButton("Simulation", mod.settings.mode == 0) then
        mod.settings.mode = 0
        Core.ClampSpeed(mod)
        Settings.Save(mod)
    end
    wu.Tooltips.Show("Speeds up the ENTIRE game simulation (NPCs, Physics, Time).\nBest for bustling city shots.")
    ImGui.SameLine()
    if ImGui.RadioButton("Clock Only", mod.settings.mode == 1) then
        mod.settings.mode = 1
        Settings.Save(mod)
    end
    wu.Tooltips.Show("Speeds up ONLY the Time of Day (Sun/Stars).\nNPCs and Traffic move at normal speed.\nBest for sunsets/sunrises.")

    wu.Controls.SectionHeader("Speed", 6, 4, nil, nil, { separatorAfter = true })
    local maxSpeed = Core.GetMaxSpeed(mod)
    local speedTooltip = "0 = pause | 0.5x = half speed | 1x = normal | 10x = the engine's maximum"
    if mod.settings.mode == 1 then
        speedTooltip = "How fast the clock moves.\n1x = real time | 60x = a game minute a second | 3600x = a game hour a second"
    end
    c:SliderFloat(IconGlyphs.Speedometer, "speed", 0.0, maxSpeed, { format = "%.1fx", tooltip = speedTooltip })

    -- Precise input, Clock mode only, where the range runs to 10000x.
    if mod.settings.mode == 1 then
        local inSpeed, inChanged = wu.Controls.InputFloat(IconGlyphs.Keyboard, "SpeedInput", mod.settings.speed, {
            step = 1.0,
            stepFast = 10.0,
            format = "%.1f",
            tooltip = "Type a speed for the clock.",
        })
        if inChanged then
            mod.settings.speed = math.max(0.0, math.min(inSpeed, maxSpeed))
            Settings.Save(mod)
        end
    end

    local quickSpeeds = { 0.5, 2, 5, 10 }
    if mod.settings.mode == 1 then quickSpeeds = { 1, 60, 600, 3600 } end

    local speedRow = {}
    for i, s in ipairs(quickSpeeds) do
        speedRow[i] = {
            label = s .. "x",
            style = (mod.settings.speed == s) and "active" or "inactive",
            onClick = function()
                mod.settings.speed = s
                Settings.Save(mod)
            end,
        }
    end
    wu.Controls.ButtonRow(speedRow, { normalSpacing = true })
    ImGui.EndDisabled()

    wu.Controls.SectionHeader("Duration", 6, 4, nil, nil, { separatorAfter = true })
    local halfW = (bodyW - spacing) / 2
    ImGui.PushItemWidth(halfW)
    local val, changed = wu.Controls.InputFloat(IconGlyphs.TimerSand, "DurInput", mod.ui.durationVal, {
        step = 0.25,
        stepFast = 1.0,
        tooltip = "How long the run lasts in real time.\nSet it to 0 to run until you stop it.",
    })
    if changed then
        mod.ui.durationVal = math.max(0, val)
        Core.RecalcDuration(mod)
        Settings.Save(mod)
    end
    ImGui.PopItemWidth()
    ImGui.SameLine()
    ImGui.PushItemWidth(halfW)
    local unit, unitChanged = wu.Controls.Combo(nil, "DurUnit", mod.ui.durationUnit, mod.ui.unitLabels)
    if unitChanged then
        mod.ui.durationUnit = unit
        Core.RecalcDuration(mod)
        Settings.Save(mod)
    end
    ImGui.PopItemWidth()

    c:SliderFloat(IconGlyphs.TimerOutline, "startDelay", 0.0, 30.0, {
        format = "%.1fs",
        tooltip = "Wait this many seconds after Start before the time-lapse begins, so you can close the overlay.",
    })

    wu.Controls.SectionHeader("Start Time", 6, 4, nil, nil, { separatorAfter = true })
    local comboW = (bodyW * 0.28)

    ImGui.PushItemWidth(comboW)
    local hour, hourChanged = wu.Controls.Combo(IconGlyphs.CalendarClock, "Hour", mod.settings.comboHour, HOURS)
    if hourChanged then
        mod.settings.comboHour = hour
        Settings.Save(mod)
    end
    ImGui.SameLine()
    local minute, minuteChanged = wu.Controls.Combo(nil, "Minute", mod.settings.comboMinute, MINUTES)
    if minuteChanged then
        mod.settings.comboMinute = minute
        Settings.Save(mod)
    end
    ImGui.PopItemWidth()
    ImGui.SameLine()
    wu.Controls.ButtonRow({
        {
            label = "AM",
            style = (mod.settings.comboAmPm == 0) and "active" or "inactive",
            onClick = function()
                mod.settings.comboAmPm = 0
                Settings.Save(mod)
            end,
        },
        {
            label = "PM",
            style = (mod.settings.comboAmPm == 1) and "active" or "inactive",
            onClick = function()
                mod.settings.comboAmPm = 1
                Settings.Save(mod)
            end,
        },
    }, { normalSpacing = true })

    local function TimePreset(label, hourIndex, amPm)
        return {
            label = label,
            onClick = function()
                mod.settings.comboHour = hourIndex
                mod.settings.comboMinute = 0
                mod.settings.comboAmPm = amPm
                Settings.Save(mod)
                Core.SetTimeNow(mod)
            end,
        }
    end
    wu.Controls.ButtonRow({
        TimePreset("6 AM", 5, 0), TimePreset("12 PM", 11, 1), TimePreset("6 PM", 5, 1), TimePreset("12 AM", 11, 0),
    }, { normalSpacing = true })

    if wu.Controls.FullWidthButton(IconGlyphs.DebugStepOver .. " Set Time Now") then
        Core.SetTimeNow(mod)
    end
    wu.Tooltips.Show("Sets the in-game time to the hour and minute above, right now.")

    c:Checkbox(IconGlyphs.History .. " Set Time on Start", "useStartTime",
        { tooltip = "When the time-lapse starts, set the game time to the hour and minute above." })
    if mod.settings.useStartTime then
        c:Checkbox(IconGlyphs.Restore .. " Restore Time on Stop", "restoreTime",
            { tooltip = "When the time-lapse stops, put the game time back to what it was before Start." })
    end
end

local function DrawSceneTab(mod, c)
    wu.Controls.SectionHeader("The city", nil, 4, nil, nil, { separatorAfter = true })
    c:Checkbox(IconGlyphs.AirplaneOff .. " Disable Air Traffic", "disableAirTraffic",
        { tooltip = "Stops flying AVs during the run.\nAVs already in the air need time to clear." })
    c:Checkbox(IconGlyphs.AccountGroupOutline .. " Disable Crowds & Traffic", "disableCrowds",
        { tooltip = "Stops ambient pedestrians and street vehicles during the run.\nOnes already spawned need time to clear." })

    wu.Controls.SectionHeader("Traffic Frenzy", 6, 4, nil, nil, { separatorAfter = true })
    c:Checkbox(IconGlyphs.Speedometer .. " Traffic Frenzy (Experimental)", "forceVehicleDilation",
        { tooltip = "Speeds up ambient traffic during a Simulation run by sending cars their own drive commands.\n\n" ..
            "While it is on:\n" ..
            " - Collision damage is off, so cars bounce instead of crumpling\n" ..
            " - Overlapping cars despawn to clear jams\n" ..
            " - Safety distance is raised\n" ..
            " - Cars recycle faster to hold the traffic density\n\n" ..
            "Traffic smooths out the longer the run goes.\n\n" ..
            "EXPECT JANK: cars may corner hard, stop briefly, or behave oddly." })

    if mod.settings.forceVehicleDilation then
        ImGui.BeginDisabled(mod.isActive)
        c:SliderFloat(IconGlyphs.CarSpeedLimiter, "frenzySpeedMult", 1.0, 20.0, {
            format = "%.1fx",
            tooltip = "How fast traffic moves, separate from the time dilation.\n1.5x suits 10x dilation. Higher is faster and jankier.",
        })
        ImGui.EndDisabled()
    else
        wu.Controls.TextMuted("Simulation mode only.")
    end
end

local function DrawAudioTab(mod, c)
    wu.Controls.SectionHeader("Muted for the run", nil, 4, nil, nil, { separatorAfter = true })
    c:Checkbox(IconGlyphs.RadioOff .. " Mute Radio", "muteRadio",
        { tooltip = "Silences the Radioport and the car radio for the run, and puts both levels back on Stop." })
    c:Checkbox(IconGlyphs.MusicNoteOff .. " Mute Music", "muteMusic",
        { tooltip = "Silences the game's own score for the run." })
    c:Checkbox(IconGlyphs.VolumeOff .. " Mute Sound Effects", "muteSfx",
        { tooltip = "Silences sound effects for the run, city ambience and this mod's own cues included." })
    c:Checkbox(IconGlyphs.BellOff .. " Mute Notifications", "muteNotifications",
        { tooltip = "Silences message, quest and side popups for the run.\nA call that arrives during a run has its ringtone cut the moment it starts." })

    wu.Controls.SectionHeader("This mod", 6, 4, nil, nil, { separatorAfter = true })
    c:Checkbox(IconGlyphs.VolumeHigh .. " Audio Cues", "playAudio",
        { tooltip = "Play the countdown and finish sounds." })
    c:Checkbox(IconGlyphs.MessageTextOutline .. " Messages", "showMessages",
        { tooltip = "Show this mod's status messages on screen." })
end

local function DrawPlayerTab(mod, HudUtils, c)
    wu.Controls.SectionHeader("Hold the shot", nil, 4, nil, nil, { separatorAfter = true })
    c:Checkbox(IconGlyphs.Walk .. " Lock Movement", "lockMovement",
        { tooltip = "Stops V moving during the run, so the frame cannot drift." })
    c:Checkbox(IconGlyphs.Pistol .. " Lock Weapons", "lockWeapons",
        { tooltip = "Stops V drawing or firing a weapon during the run.\nIt also empties V's hands, which silences the Radioport." })
    c:Checkbox(IconGlyphs.Eye .. " Lock Camera", "lockCamera",
        { tooltip = "Stops the camera turning during the run, for a static frame." })
    c:Checkbox(IconGlyphs.CameraOutline .. " No Head Bob", "disableHeadBob",
        { tooltip = "Turns off additive camera motion during the run, for a steady shot." })

    wu.Controls.SectionHeader("HUD", 6, 4, nil, nil, { separatorAfter = true })
    c:Checkbox(IconGlyphs.EyeOff .. " Auto-Hide HUD", "autoHideHud",
        { tooltip = "Hides the HUD and notifications while the run goes, and shows them again on Stop.\nThe Toggle HUD hotkey and the button below work at any time." })
    c:Checkbox(IconGlyphs.ShieldOutline .. " Block Start in Combat", "blockInCombat",
        { tooltip = "Refuses to start a time-lapse while you are in combat.\nUntick to allow a run during combat." })

    local hudLabel = IconGlyphs.EyeOff .. " Hide HUD"
    if mod.hudHidden then hudLabel = IconGlyphs.Eye .. " Restore HUD" end
    if wu.Controls.FullWidthButton(hudLabel, mod.hudHidden and "active" or "inactive") then
        HudUtils.Toggle(mod)
    end
end

local function DrawDebugTab(mod, Core, HudUtils, CameraUtils)
    wu.Controls.SectionHeader("Panic controls", nil, 4, nil, nil, { separatorAfter = true })
    wu.Controls.ButtonRow({
        {
            label = IconGlyphs.Walk .. " Unlock Movement",
            tooltip = "Removes the movement lock. Use if V is stuck in place.",
            onClick = function() CameraUtils.UnlockMovement(mod) end,
        },
        {
            label = IconGlyphs.Eye .. " Unlock Camera",
            tooltip = "Removes the camera lock. Use if you cannot look around.",
            onClick = function() CameraUtils.UnlockCamera(mod) end,
        },
    }, { normalSpacing = true })
    wu.Controls.ButtonRow({
        {
            label = IconGlyphs.Eye .. " Restore HUD",
            tooltip = "Brings the HUD back even if the mod has lost track of hiding it.",
            onClick = function() HudUtils.ForceRestore(mod) end,
        },
        {
            label = IconGlyphs.Camera .. " Force Head Bob",
            tooltip = "Puts additive camera motion back to full.",
            onClick = function() CameraUtils.ForceRestore(mod) end,
        },
    }, { normalSpacing = true })
    wu.Controls.ButtonRow({
        {
            label = IconGlyphs.VolumeHigh .. " Restore Audio",
            tooltip = "Puts every volume this mod can mute back to full and gives the popups their sound back.",
            onClick = function()
                AudioUtils.ForceRestore()
                Notifications.ForceRestore()
            end,
        },
    }, { normalSpacing = true })

    wu.Controls.SectionHeader("Logging", 6, 4, nil, nil, { separatorAfter = true })
    local levelIndex = 0
    for i, name in ipairs(Log.LEVELS) do
        if name == mod.settings.logLevel then levelIndex = i - 1 end
    end
    local newIndex, levelChanged = wu.Controls.Combo(IconGlyphs.FileDocumentOutline, "LogLevel", levelIndex, Log.LEVELS, {
        tooltip = "What the mod writes to the CET console and its log file.\nWarn shows only problems. Info adds start and stop. Debug adds everything.",
    })
    if levelChanged then
        mod.settings.logLevel = Log.LEVELS[newIndex + 1]
        Log.SetLevel(mod.settings.logLevel)
        Settings.Save(mod)
    end

    wu.Controls.SectionHeader("Last run", 6, 4, nil, nil, { separatorAfter = true })
    if mod.lastRunStats.valid then
        wu.Controls.StatusBar("Speed setting", string.format("%.1fx", mod.lastRunStats.speedSetting))
        wu.Controls.StatusBar("Real duration", string.format("%.2fs", mod.lastRunStats.durationReal))
        wu.Controls.StatusBar("Game time passed", Core.FormatDuration(mod.lastRunStats.timePassedGame))
        wu.Controls.StatusBar("Game time expected", Core.FormatDuration(mod.lastRunStats.timeExpectedGame))
        ImGui.PushTextWrapPos(0.0)
        if mod.lastRunStats.mode == 0 then
            wu.Controls.TextMuted(
                "Day Curve Match is the game time gained against the vanilla day curve. A mod that changes the length of the day moves it away from 100%, and a run of a few seconds reads rough because game time is counted in whole seconds.")
        else
            wu.Controls.TextMuted(
                "Clock Efficiency is how closely the clock moved at the speed asked for. Below 100% means the script could not keep up.")
        end
        ImGui.PopTextWrapPos()
    else
        wu.Controls.TextMuted("No run recorded yet.")
    end

    wu.Controls.Separator(6, 4)
    local verWidth = ImGui.CalcTextSize(mod.version)
    local availW = ImGui.GetContentRegionAvail()
    ImGui.SetCursorPosX(ImGui.GetCursorPosX() + availW - verWidth)
    wu.Controls.TextMuted(mod.version)
end

-- =================================================================
-- ### STATUS AND FOOTER ###
-- =================================================================

local function DrawStatusLine(mod)
    if mod.isActive then
        wu.Controls.TextSuccess(IconGlyphs.PlayCircleOutline .. " RUNNING")
        ImGui.SameLine()
        if mod.settings.duration > 0 then
            ImGui.Text(string.format("%.1fs of %.1fs", mod.elapsedTime, mod.settings.duration))
            wu.Controls.ProgressBar(mod.elapsedTime / mod.settings.duration, -1, 4, nil, "success")
        else
            ImGui.Text(string.format("%.1fs, no end set", mod.elapsedTime))
        end
    elseif mod.isDelaying then
        wu.Controls.TextWarning(IconGlyphs.TimerSand .. " STARTING IN " .. string.format("%.1f", mod.delayTimer) .. "s")
    else
        wu.Controls.TextWarning(IconGlyphs.StopCircleOutline .. " READY")
    end
end

--- The last run's outcome in one line. The full numbers are in the Debug tab.
local function DrawLastRun(mod, Core)
    if not mod.lastRunStats.valid then return end

    wu.Controls.TextMuted(string.format("Last run: %.1fs real, %s game",
        mod.lastRunStats.durationReal, Core.FormatDuration(mod.lastRunStats.timePassedGame)))
    ImGui.SameLine()

    local f = mod.lastRunStats.factor
    if not f then
        wu.Controls.TextMuted("n/a")
    elseif math.abs(f - 1) > 0.1 then
        wu.Controls.TextDanger(string.format("%.1f%%", f * 100))
    elseif math.abs(f - 1) > 0.02 then
        wu.Controls.TextWarning(string.format("%.1f%%", f * 100))
    else
        wu.Controls.TextSuccess(string.format("%.1f%%", f * 100))
    end
    wu.Tooltips.Show(mod.lastRunStats.mode == 0 and "Day curve match" or "Clock efficiency")
end

local function DrawFooter(mod, Core, HudUtils)
    local footerTop = ImGui.GetCursorPosY()
    local estData = Core.GetEstimatedData(mod)

    wu.Controls.Separator(2, 2)
    ImGui.Text("Now " .. Core.GetGameTimeStr())
    ImGui.SameLine()
    ImGui.Text("to")
    ImGui.SameLine()
    local colors = wu.Styles.colors
    ImGui.TextColored(colors.green[1], colors.green[2], colors.green[3], 1, estData.endTime)
    if mod.settings.mode == 0 then
        wu.Tooltips.Show("The game clock runs slower around dawn and dusk. The estimate uses the vanilla day curve,\nso a mod that changes the length of the day makes it inaccurate.")
    end
    ImGui.SameLine()
    wu.Controls.TextMuted("(" .. estData.durStr .. ")")

    if mod.settings.useStartTime then
        wu.Controls.TextMuted("Starts at " .. estData.startTimeStr)
    end

    DrawLastRun(mod, Core)

    if mod.isActive or mod.isDelaying then
        if wu.Controls.FullWidthButton(IconGlyphs.Stop .. " STOP", "danger") then Core.Stop(mod, HudUtils) end
    else
        if wu.Controls.FullWidthButton(IconGlyphs.Play .. " START", "active") then Core.Start(mod, HudUtils) end
    end

    footerHeight = ImGui.GetCursorPosY() - footerTop - ImGui.GetStyle().ItemSpacing.y
end

-- =================================================================
-- ### DRAW ###
-- =================================================================

function UI.Draw(mod, Core, HudUtils, CameraUtils)
    if not mod.isOverlayOpen then return end

    wu = wu or GetMod("WindowUtils")
    if not wu then
        DrawMissingDependency()
        return
    end
    binding = binding or wu.Controls.bind(mod.settings, mod.defaults, function() Settings.Save(mod) end)

    wu.SetConstraints(420, 400, 4000, 4000, WINDOW_NAME)
    ImGui.SetNextWindowSize(440, 800, ImGuiCond.FirstUseEver)

    -- First return is the title-bar close button, second is visibility (false while collapsed).
    local open, visible = wu.Begin(WINDOW_NAME, true)
    if not open then
        -- Hidden until the CET overlay next opens.
        mod.isOverlayOpen = false
    end

    if visible then
        local spacing = ImGui.GetStyle().ItemSpacing.x

        DrawStatusLine(mod)
        DrawPresetRow(mod, Core, spacing)

        wu.Tabs.bar("MainTabs", {
            {
                label = IconGlyphs.MovieRoll .. " Shot",
                content = function() TabBody("ShotBody", function() DrawShotTab(mod, Core, binding, spacing) end) end,
            },
            {
                label = IconGlyphs.CityVariantOutline .. " Scene",
                content = function() TabBody("SceneBody", function() DrawSceneTab(mod, binding) end) end,
            },
            {
                label = IconGlyphs.VolumeHigh .. " Audio",
                content = function() TabBody("AudioBody", function() DrawAudioTab(mod, binding) end) end,
            },
            {
                label = IconGlyphs.AccountOutline .. " Player",
                content = function() TabBody("PlayerBody", function() DrawPlayerTab(mod, HudUtils, binding) end) end,
            },
            {
                label = IconGlyphs.Bug .. " Debug",
                content = function() TabBody("DebugBody", function() DrawDebugTab(mod, Core, HudUtils, CameraUtils) end) end,
            },
        })

        DrawFooter(mod, Core, HudUtils)
    end
    wu.End()
end

return UI
