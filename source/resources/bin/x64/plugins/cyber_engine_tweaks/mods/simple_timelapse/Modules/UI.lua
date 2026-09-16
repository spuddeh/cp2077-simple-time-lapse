-- ======================================================================================
-- Simple Time-lapse - UI Module
-- Mod Version:  v1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- The whole window, drawn with Window Utils, a required dependency. Controls, colours
-- and spacing come from the library rather than raw ImGui wherever it offers them.
-- Layout: status line, preset row and the run summary pinned at the top, a column of
-- section buttons beside the section's own scrolling pane, and the clock readout with
-- START pinned at the bottom. The summary shows what a run will do from any section.
-- ======================================================================================

local Log = require("Modules/Log")
local Settings = require("Modules/Settings")
local AudioUtils = require("Modules/AudioUtils")
local Notifications = require("Modules/Notifications")
local Presets = require("Modules/Presets")

local UI = {}

local WINDOW_NAME = "Simple Time-lapse"

-- Width of the section column, and the smallest the pane beside it may get.
local NAV_WIDTH = 132
local MIN_PANE_HEIGHT = 120

-- Every slider and drag here types a value on Ctrl+click, which is ImGui's own binding.
local TYPE_HINT = "\nCtrl+click to type a value."

local wu = nil
local binding = nil

-- Height of the pinned footer, measured each frame and used to size the panes on the next.
local footerHeight = 120

local section = 1

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

-- =================================================================
-- ### PRESETS ###
-- =================================================================

local function SelectedPresetName()
    return Presets.Names()[presetIndex + 1]
end

local function DrawPresetRow(mod, Core)
    local names = Presets.Names()
    if presetIndex > #names - 1 then presetIndex = math.max(#names - 1, 0) end

    local selected = SelectedPresetName()
    local buttonW = 78

    ImGui.BeginDisabled(mod.isActive)
    local newIndex, changed = wu.Controls.Combo(IconGlyphs.FolderStarOutline, "Preset", presetIndex, names, {
        cols = 7,
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
            label = "Save As",
            width = buttonW,
            disabled = mod.isActive and "hard" or nil,
            tooltip = "Saves the options as they stand under a name you type.\nTyping a name that already exists replaces it.",
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
        nameInput = wu.Controls.InputText(IconGlyphs.RenameBox, "PresetName", nameInput, {
            cols = 7,
            maxLength = 64,
            tooltip = "Name this preset.",
        })

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
-- ### SUMMARY ###
-- =================================================================

--- One icon standing for an option the run will apply, with its meaning on hover.
local function Chip(icon, text)
    wu.Controls.TextMuted(icon)
    wu.Tooltips.Show(text)
    ImGui.SameLine()
end

--- What the run will do, whichever section is open.
local function DrawSummary(mod, Core)
    local s = mod.settings

    local speed = string.format("%.1fx", s.speed)
    local mode = s.mode == 0 and "Simulation" or "Clock only"
    local length = s.duration > 0 and Core.FormatDuration(s.duration) or "until stopped"
    ImGui.Text(mode .. " " .. speed)
    ImGui.SameLine(); wu.Controls.TextMuted("for"); ImGui.SameLine()
    ImGui.Text(length)
    if s.useStartTime then
        ImGui.SameLine(); wu.Controls.TextMuted("from"); ImGui.SameLine()
        ImGui.Text(Core.FormatSecondsToTime(Core.GetStartSeconds(mod)))
    end

    if s.disableAirTraffic then Chip(IconGlyphs.AirplaneOff, "Air traffic off") end
    if s.disableCrowds then Chip(IconGlyphs.AccountGroupOutline, "Crowds and street traffic off") end
    if s.forceVehicleDilation and s.mode == 0 then
        Chip(IconGlyphs.CarSpeedLimiter, string.format("Traffic Frenzy at %.1fx", s.frenzySpeedMult))
    end
    if s.muteRadio then Chip(IconGlyphs.RadioOff, "Radio muted") end
    if s.muteMusic then Chip(IconGlyphs.MusicNoteOff, "Music muted") end
    if s.muteSfx then Chip(IconGlyphs.VolumeOff, "Sound effects muted") end
    if s.muteNotifications then Chip(IconGlyphs.BellOff, "Notifications silenced, call ringtone cut") end
    if s.autoHideHud then Chip(IconGlyphs.EyeOff, "HUD hidden for the run") end
    if s.lockMovement then Chip(IconGlyphs.Walk, "Movement locked") end
    if s.lockWeapons then Chip(IconGlyphs.Pistol, "Weapons locked") end
    if s.lockCamera then Chip(IconGlyphs.Eye, "Camera locked") end
    if s.disableHeadBob then Chip(IconGlyphs.CameraOutline, "Head bob off") end
    if s.useStartTime and s.restoreTime then Chip(IconGlyphs.Restore, "Game time put back on Stop") end
    if s.startDelay > 0 then Chip(IconGlyphs.TimerOutline, string.format("%.1fs countdown", s.startDelay)) end
    ImGui.NewLine()
end

-- =================================================================
-- ### SECTIONS ###
-- =================================================================

-- Time units, shared by the duration and the Clock-mode speed. Index is the unit + 1.
local UNIT_SECONDS = { 1, 60, 3600 }
local UNIT_WORD = { "second", "minute", "hour" }
local UNIT_LABEL = { "Seconds", "Minutes", "Hours" }
local DURATION_MAX = { 60, 60, 12 }
local CLOCK_MAX = { 60, 60, 2 }

--- Splits a multiplier into a value and the largest unit it divides into evenly.
local function SpeedParts(speed)
    if speed >= 3600 and speed % 3600 == 0 then return math.floor(speed / 3600), 2 end
    if speed >= 60 and speed % 60 == 0 then return math.floor(speed / 60), 1 end
    return math.max(1, math.floor(speed)), 0
end

--- Seconds / Minutes / Hours as one button each, the current unit highlighted.
local function UnitRow(unit, maxima, onPick)
    local defs = {}
    for i, label in ipairs(UNIT_LABEL) do
        defs[i] = {
            label = label,
            style = (unit == i - 1) and "active" or "inactive",
            tooltip = string.format("Up to %d %ss", maxima[i], UNIT_WORD[i]),
            onClick = function() onPick(i - 1) end,
        }
    end
    wu.Controls.ButtonRow(defs, { normalSpacing = true })
end

local function DrawShotSection(mod, Core, c)
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
    ImGui.BeginDisabled(runLocked)
    if mod.settings.mode == 0 then
        c:SliderFloat(IconGlyphs.Speedometer, "speed", 0.0, Core.GetMaxSpeed(mod), {
            format = "%.1fx",
            tooltip = "0 = pause | 0.5x = half speed | 1x = normal | 10x is the engine maximum" .. TYPE_HINT,
        })

        local speedRow = {}
        for i, sp in ipairs({ 0.5, 2, 5, 10 }) do
            speedRow[i] = {
                label = sp .. "x",
                style = (mod.settings.speed == sp) and "active" or "inactive",
                onClick = function()
                    mod.settings.speed = sp
                    Settings.Save(mod)
                end,
            }
        end
        wu.Controls.ButtonRow(speedRow, { normalSpacing = true })
    else
        -- Clock speed reads as a length of game time per real second, because a bare
        -- multiplier over four orders of magnitude is unusable on a slider.
        local value, unit = SpeedParts(mod.settings.speed)
        UnitRow(unit, CLOCK_MAX, function(newUnit)
            mod.settings.speed = math.min(value, CLOCK_MAX[newUnit + 1]) * UNIT_SECONDS[newUnit + 1]
            Core.ClampSpeed(mod)
            Settings.Save(mod)
        end)

        local newValue, changed = wu.Controls.SliderInt(IconGlyphs.Speedometer, "ClockSpeed", value, 1,
            CLOCK_MAX[unit + 1], {
                format = string.format("%d " .. UNIT_WORD[unit + 1] .. "%s per real second", value,
                    value == 1 and "" or "s"),
                tooltip = "How much game time passes each real second." .. TYPE_HINT,
            })
        if changed then
            mod.settings.speed = newValue * UNIT_SECONDS[unit + 1]
            Core.ClampSpeed(mod)
            Settings.Save(mod)
        end
        wu.Controls.TextMuted(string.format("%.0fx normal speed", mod.settings.speed))
    end
    ImGui.EndDisabled()

    wu.Controls.SectionHeader("Duration", 6, 4, nil, nil, { separatorAfter = true })
    c:Checkbox(IconGlyphs.Infinity .. " Run until stopped", "runUntilStopped", {
        tooltip = "Runs with no end, until you press Stop or the hotkey.",
        onChange = function() Core.RecalcDuration(mod) end,
    })

    if not mod.settings.runUntilStopped then
        UnitRow(mod.ui.durationUnit, DURATION_MAX, function(newUnit)
            mod.ui.durationUnit = newUnit
            mod.ui.durationVal = math.min(mod.ui.durationVal, DURATION_MAX[newUnit + 1])
            Core.RecalcDuration(mod)
            Settings.Save(mod)
        end)

        local durValue = math.max(1, math.floor(mod.ui.durationVal))
        local newDur, durChanged = wu.Controls.SliderInt(IconGlyphs.TimerSand, "DurValue", durValue, 1,
            DURATION_MAX[mod.ui.durationUnit + 1], {
                format = string.format("%d " .. UNIT_WORD[mod.ui.durationUnit + 1] .. "%s", durValue,
                    durValue == 1 and "" or "s"),
                tooltip = "How long the run lasts in real time." .. TYPE_HINT,
            })
        if durChanged then
            mod.ui.durationVal = newDur
            Core.RecalcDuration(mod)
            Settings.Save(mod)
        end
    end

    c:SliderFloat(IconGlyphs.TimerOutline, "startDelay", 0.0, 30.0, {
        format = "%.1fs",
        tooltip = "Wait this many seconds after Start before the time-lapse begins, so you can close the overlay." ..
            TYPE_HINT,
    })

    wu.Controls.SectionHeader("Start Time", 6, 4, nil, nil, { separatorAfter = true })
    local newStart, startChanged = wu.Controls.TimeDrag(IconGlyphs.CalendarClock, "StartTime", mod.settings.startSeconds, {
        tooltip = "The time of day a run starts from.\nDrag to move it a minute at a time, or double-click and type a time such as 8:00 am.",
    })
    if startChanged then
        mod.settings.startSeconds = newStart % 86400
        Settings.Save(mod)
    end

    local function TimePreset(label, hour24)
        return {
            label = label,
            style = (mod.settings.startSeconds == hour24 * 3600) and "active" or "inactive",
            onClick = function()
                mod.settings.startSeconds = hour24 * 3600
                Settings.Save(mod)
            end,
        }
    end
    wu.Controls.ButtonRow({
        TimePreset("6 AM", 6), TimePreset("12 PM", 12), TimePreset("6 PM", 18), TimePreset("12 AM", 0),
    }, { normalSpacing = true })

    c:Checkbox(IconGlyphs.History .. " Set Time on Start", "useStartTime",
        { tooltip = "When the time-lapse starts, set the game time to the time above." })
    if mod.settings.useStartTime then
        ImGui.SameLine()
        c:Checkbox(IconGlyphs.Restore .. " Restore on Stop", "restoreTime",
            { tooltip = "When the time-lapse stops, put the game time back to what it was before Start." })
    end

    if wu.Controls.FullWidthButton(IconGlyphs.DebugStepOver .. " Set Time Now") then
        Core.SetTimeNow(mod)
    end
    wu.Tooltips.Show("Sets the in-game time to the time above, right now.")
end

local function DrawSceneSection(mod, c)
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
            tooltip = "How fast traffic moves, separate from the time dilation.\n1.5x suits 10x dilation. Higher is faster and jankier." ..
                TYPE_HINT,
        })
        ImGui.EndDisabled()
    else
        wu.Controls.TextMuted("Simulation mode only.")
    end
end

local function DrawAudioSection(mod, c)
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

local function DrawPlayerSection(mod, HudUtils, c)
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

local function DrawDebugSection(mod, Core, HudUtils, CameraUtils)
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

--- The last run's outcome in one line. The full numbers are in the Debug section.
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
    wu.Controls.TextMuted("to")
    ImGui.SameLine()
    local colors = wu.Styles.colors
    ImGui.TextColored(colors.green[1], colors.green[2], colors.green[3], 1, estData.endTime)
    if mod.settings.mode == 0 then
        wu.Tooltips.Show("The game clock runs slower around dawn and dusk. The estimate uses the vanilla day curve,\nso a mod that changes the length of the day makes it inaccurate.")
    end
    ImGui.SameLine()
    wu.Controls.TextMuted("(" .. estData.durStr .. ")")

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

    wu.SetConstraints(480, 460, 4000, 4000, WINDOW_NAME)
    ImGui.SetNextWindowSize(520, 760, ImGuiCond.FirstUseEver)

    -- First return is the title-bar close button, second is visibility (false while collapsed).
    local open, visible = wu.Begin(WINDOW_NAME, true)
    if not open then
        -- Hidden until the CET overlay next opens.
        mod.isOverlayOpen = false
    end

    if visible then

        DrawStatusLine(mod)
        DrawPresetRow(mod, Core)
        wu.Controls.Separator(2, 2)
        DrawSummary(mod, Core)

        local sections = {
            { label = IconGlyphs.MovieRoll .. " Shot",   draw = function() DrawShotSection(mod, Core, binding) end },
            { label = IconGlyphs.CityVariantOutline .. " Scene", draw = function() DrawSceneSection(mod, binding) end },
            { label = IconGlyphs.VolumeHigh .. " Audio", draw = function() DrawAudioSection(mod, binding) end },
            { label = IconGlyphs.AccountOutline .. " Player", draw = function() DrawPlayerSection(mod, HudUtils, binding) end },
            { label = IconGlyphs.Bug .. " Debug",        draw = function() DrawDebugSection(mod, Core, HudUtils, CameraUtils) end },
        }

        local _, availH = ImGui.GetContentRegionAvail()
        local spacingY = ImGui.GetStyle().ItemSpacing.y
        local paneHeight = math.max(availH - footerHeight - spacingY * 2, MIN_PANE_HEIGHT)

        wu.Controls.Row("Main", {
            {
                width = NAV_WIDTH,
                content = function()
                    for i, entry in ipairs(sections) do
                        if wu.Controls.FullWidthButton(entry.label, (section == i) and "active" or "inactive") then
                            section = i
                        end
                    end
                end,
            },
            {
                flex = 1,
                border = true,
                content = function() sections[section].draw() end,
            },
        }, { height = paneHeight, normalSpacing = true })

        DrawFooter(mod, Core, HudUtils)
    end
    wu.End()
end

return UI
