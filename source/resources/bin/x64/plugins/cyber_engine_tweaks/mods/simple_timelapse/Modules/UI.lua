-- ======================================================================================
-- Simple Time-lapse - UI Module
-- Mod Version:  v1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- The whole window, drawn with Window Utils, a required dependency. Layout: a status
-- line and the preset row pinned at the top, a scrolling body of panels, and the clock
-- readout with START pinned at the bottom. The Shot panel holds what changes every
-- take; everything else starts collapsed.
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

--- A collapsing section whose contents sit in a panel.
local function Section(id, label, defaultOpen, contentFn)
    ImGui.SetNextItemOpen(defaultOpen, ImGuiCond.FirstUseEver)
    if ImGui.CollapsingHeader(label) then
        wu.Controls.PanelGroup(id, contentFn)
    end
    ImGui.Spacing()
end

-- =================================================================
-- ### PRESETS ###
-- =================================================================

local function SelectedPresetName()
    return Presets.Names()[presetIndex + 1]
end

local function DrawPresetRow(mod, Core, spacing)
    local names = Presets.Names()
    local items = names
    if #names == 0 then items = { "No presets saved" } end
    if presetIndex > #names - 1 then presetIndex = math.max(#names - 1, 0) end

    local availW = ImGui.GetContentRegionAvail()
    local buttonW = 74
    local comboW = availW - (buttonW + spacing) * 2

    ImGui.SetNextItemWidth(comboW)
    ImGui.BeginDisabled(#names == 0 or mod.isActive)
    local newIndex, changed = ImGui.Combo("##Preset", presetIndex, items, #items)
    if changed then
        presetIndex = newIndex
        local name = SelectedPresetName()
        if name then
            Presets.Apply(mod, name, Core)
            Settings.Save(mod)
            Core.PlaySound(mod, "ui_menu_click")
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip("Loads a saved set of options.\nA preset carries every setting except the log level and Traffic Frenzy.")
    end
    ImGui.EndDisabled()

    ImGui.SameLine()
    ImGui.BeginDisabled(mod.isActive)
    if ImGui.Button("Save", buttonW, 0) then
        naming = true
        nameInput = SelectedPresetName() or ""
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip("Saves the current options under a name you type.\nAn existing name is replaced.")
    end
    ImGui.EndDisabled()

    ImGui.SameLine()
    wu.Controls.ButtonRow({
        {
            label = "Delete",
            type = "hold",
            width = buttonW,
            style = "danger",
            disabled = (#names == 0 or mod.isActive) and "hard" or nil,
            holdDuration = 1.0,
            progressDisplay = "overlay",
            tooltip = "Hold to delete the selected preset.",
            onHold = function()
                local name = SelectedPresetName()
                if name and Presets.Delete(name) then
                    presetIndex = 0
                    Core.PlaySound(mod, "ui_menu_click")
                end
            end,
        },
    })

    if naming then
        ImGui.SetNextItemWidth(comboW)
        local text = ImGui.InputText("##PresetName", nameInput, 64)
        nameInput = text

        ImGui.SameLine()
        local confirmed = ImGui.Button("Confirm", buttonW, 0)
        ImGui.SameLine()
        if ImGui.Button("Cancel", buttonW, 0) then naming = false end

        if confirmed and nameInput ~= "" then
            if Presets.Save(mod, nameInput) then
                for i, name in ipairs(Presets.Names()) do
                    if name == nameInput then presetIndex = i - 1 end
                end
                naming = false
                Core.PlaySound(mod, "ui_menu_click")
            end
        end
    end
end

-- =================================================================
-- ### PANELS ###
-- =================================================================

local function DrawShotPanel(mod, Core, c, spacing)
    local bodyW = ImGui.GetContentRegionAvail()
    local runLocked = mod.isActive

    if runLocked then
        ImGui.TextDisabled("Mode and speed are locked while a time-lapse runs.")
    end

    -- MODE
    ImGui.BeginDisabled(runLocked)
    if ImGui.RadioButton("Simulation", mod.settings.mode == 0) then
        mod.settings.mode = 0
        Core.ClampSpeed(mod)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip("Speeds up the ENTIRE game simulation (NPCs, Physics, Time). \nBest for bustling city shots.")
    end
    ImGui.SameLine()
    if ImGui.RadioButton("Clock Only", mod.settings.mode == 1) then mod.settings.mode = 1 end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip("Speeds up ONLY the Time of Day (Sun/Stars). \nNPCs and Traffic move at normal speed. \nBest for sunsets/sunrises.")
    end

    -- SPEED
    ImGui.Spacing()
    ImGui.Text(IconGlyphs.Speedometer .. " Speed")
    ImGui.SetNextItemWidth(bodyW)

    local maxSpeed = Core.GetMaxSpeed(mod)
    local speedTooltip = "0 = Pause | 0.5x = Half Speed | 1x = Normal | 10x = the engine's maximum"
    if mod.settings.mode == 1 then
        speedTooltip =
        "Controls how fast the clock moves.\n1x = Real Time | 60x = 1 Game Minute per Real Second | 3600x = 1 Game Hour per Real Second"
    end

    local newSpeed, speedChanged = ImGui.SliderFloat("##SpeedSlider", mod.settings.speed, 0.0, maxSpeed, "%.1fx")
    if speedChanged then mod.settings.speed = newSpeed end
    if ImGui.IsItemHovered() then ImGui.SetTooltip(speedTooltip) end

    -- Precise input, Clock mode only, where the range runs to 10000x.
    if mod.settings.mode == 1 then
        ImGui.SetNextItemWidth(bodyW)
        local inSpeed, inChanged = ImGui.InputFloat("##SpeedInput", mod.settings.speed, 1.0, 10.0, "%.1f")
        if inChanged then mod.settings.speed = math.max(0.0, math.min(inSpeed, maxSpeed)) end
        if ImGui.IsItemHovered() then ImGui.SetTooltip("Type a specific value here for precise control.") end
    end

    local quickSpeeds = { 0.5, 2, 5, 10 }
    if mod.settings.mode == 1 then quickSpeeds = { 1, 60, 600, 3600 } end

    local speedRow = {}
    for i, s in ipairs(quickSpeeds) do
        speedRow[i] = { label = s .. "x", onClick = function() mod.settings.speed = s end }
    end
    wu.Controls.ButtonRow(speedRow, { normalSpacing = true })
    ImGui.EndDisabled()

    -- DURATION
    ImGui.Spacing()
    ImGui.Text(IconGlyphs.TimerSand .. " Duration")
    local halfW = (bodyW - spacing) / 2
    ImGui.PushItemWidth(halfW)
    local val, changed = ImGui.InputFloat("##DurInput", mod.ui.durationVal, 0.25, 1.0, "%.2f")
    if changed then
        mod.ui.durationVal = math.max(0, val); Core.RecalcDuration(mod)
    end
    ImGui.PopItemWidth()
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip("Total real-time duration for the time-lapse session.\nSet to 0 for Infinite Mode.")
    end
    ImGui.SameLine(); ImGui.PushItemWidth(halfW)
    local unit, unitChanged = ImGui.Combo("##DurUnit", mod.ui.durationUnit, mod.ui.unitLabels, #mod.ui.unitLabels)
    if unitChanged then
        mod.ui.durationUnit = unit; Core.RecalcDuration(mod)
    end
    ImGui.PopItemWidth()

    -- START DELAY
    ImGui.Spacing()
    ImGui.Text(IconGlyphs.TimerOutline .. " Start Delay")
    c:SliderFloat(nil, "startDelay", 0.0, 30.0, {
        format = "%.1fs",
        tooltip = "Wait this many seconds after pressing Start before the time-lapse actually begins.",
    })

    -- START TIME
    ImGui.Spacing()
    ImGui.Text(IconGlyphs.CalendarClock .. " Start Time")
    local comboW = (bodyW * 0.3) - spacing

    ImGui.PushItemWidth(comboW)
    mod.settings.comboHour = ImGui.Combo("##Hour", mod.settings.comboHour, HOURS, #HOURS); ImGui.SameLine()
    mod.settings.comboMinute = ImGui.Combo("##Minute", mod.settings.comboMinute, MINUTES, #MINUTES); ImGui.SameLine()
    if ImGui.RadioButton("AM", mod.settings.comboAmPm == 0) then mod.settings.comboAmPm = 0 end; ImGui.SameLine()
    if ImGui.RadioButton("PM", mod.settings.comboAmPm == 1) then mod.settings.comboAmPm = 1 end
    ImGui.PopItemWidth()

    local function TimePreset(label, hour, amPm)
        return {
            label = label,
            onClick = function()
                mod.settings.comboHour = hour; mod.settings.comboMinute = 0; mod.settings.comboAmPm = amPm
                Core.SetTimeNow(mod)
            end
        }
    end
    wu.Controls.ButtonRow({
        TimePreset("6 AM", 5, 0), TimePreset("12 PM", 11, 1), TimePreset("6 PM", 5, 1), TimePreset("12 AM", 11, 0),
    }, { normalSpacing = true })

    ImGui.Spacing()
    if ImGui.Button(IconGlyphs.DebugStepOver .. " Set Time Now", -1, 0) then
        Core.SetTimeNow(mod)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip("Immediately sets the in-game time to the selected Hour/Minute.")
    end

    c:Checkbox(IconGlyphs.History .. " Set Time on Start", "useStartTime",
        { tooltip = "When time-lapse starts, instantly set game time to the Hour/Minute selected above." })
    if mod.settings.useStartTime then
        c:Checkbox(IconGlyphs.Restore .. " Restore Time on Stop", "restoreTime",
            { tooltip = "When time-lapse stops, sets the game time back to what it was before Start." })
    end
end

local function DrawScenePanel(mod, c)
    c:Checkbox(IconGlyphs.AirplaneOff .. " Disable Air Traffic", "disableAirTraffic",
        { tooltip = "Disables flying AVs/cars during time-lapse.\nNOTE: You may need to run the time-lapse for longer to clear out existing AVs" })
    c:Checkbox(IconGlyphs.AccountGroupOutline .. " Disable Crowds & Traffic", "disableCrowds",
        { tooltip = "Disables ambient pedestrians and street vehicles during time-lapse.\nNOTE: You may need to run the time-lapse for longer to clear out existing traffic/NPCs" })
    c:Checkbox(IconGlyphs.Speedometer .. " Traffic Frenzy (Experimental)", "forceVehicleDilation",
        { tooltip = "Speeds up ambient traffic during Simulation mode via AI command injection.\n\n" ..
            "While active, the following overrides are applied:\n" ..
            " - Collision damage disabled (vehicles bounce instead of crumpling)\n" ..
            " - Overlapping vehicles auto-despawn to clear jams\n" ..
            " - Safety measures enabled with increased buffer distance\n" ..
            " - Faster despawn recycling to maintain traffic density\n\n" ..
            "Traffic smooths out the longer the time-lapse runs.\n\n" ..
            "EXPECT JANK: Cars may corner aggressively, briefly stop, or behave unusually." })

    if mod.settings.forceVehicleDilation then
        ImGui.BeginDisabled(mod.isActive)
        c:SliderFloat(nil, "frenzySpeedMult", 1.0, 20.0, {
            format = "%.1fx",
            tooltip = "Controls how fast traffic moves. Decoupled from time dilation speed.\n" ..
                "1.5x looks best with 10x dilation. Higher values = faster but jankier.",
        })
        ImGui.EndDisabled()
    end
end

local function DrawAudioPanel(mod, c)
    c:Checkbox(IconGlyphs.RadioOff .. " Mute Radio", "muteRadio",
        { tooltip = "Silences the Radioport and the car radio for the run, and puts both levels back on Stop." })
    c:Checkbox(IconGlyphs.MusicNoteOff .. " Mute Music", "muteMusic",
        { tooltip = "Silences the game's own score for the run." })
    c:Checkbox(IconGlyphs.VolumeOff .. " Mute Sound Effects", "muteSfx",
        { tooltip = "Silences sound effects for the run, city ambience and this mod's own cues included." })
    c:Checkbox(IconGlyphs.BellOff .. " Mute Notifications", "muteNotifications",
        { tooltip = "Silences the sound of message, quest and side popups for the run.\nA call that arrives during a run has its ringtone cut the moment it starts." })
    c:Checkbox(IconGlyphs.VolumeHigh .. " Audio Cues", "playAudio",
        { tooltip = "Play sound effects for the countdown." })
    c:Checkbox(IconGlyphs.MessageTextOutline .. " Messages", "showMessages",
        { tooltip = "Show status notifications on the left side of the screen." })
end

local function DrawPlayerPanel(mod, HudUtils, c)
    c:Checkbox(IconGlyphs.Walk .. " Lock Movement", "lockMovement",
        { tooltip = "Prevents player movement during time-lapse to avoid accidental shifts." })
    c:Checkbox(IconGlyphs.Pistol .. " Lock Weapons", "lockWeapons",
        { tooltip = "Stops V drawing or firing a weapon during the run.\nIt also empties V's hands, which silences the Radioport." })
    c:Checkbox(IconGlyphs.Eye .. " Lock Camera", "lockCamera",
        { tooltip = "Prevents camera rotation during time-lapse to ensure a static frame." })
    c:Checkbox(IconGlyphs.CameraOutline .. " No Head Bob", "disableHeadBob",
        { tooltip = "Disables Additive Camera Motions (Head Bobbing) during time-lapse for a steady shot." })
    c:Checkbox(IconGlyphs.EyeOff .. " Auto-Hide HUD", "autoHideHud",
        { tooltip = "Hides the HUD and notifications when the time-lapse starts, and shows them again when it stops.\nThe Toggle HUD hotkey and the button below still work at any time." })
    c:Checkbox(IconGlyphs.ShieldOutline .. " Block Start in Combat", "blockInCombat",
        { tooltip = "Refuses to start a time-lapse while you are in combat.\nUntick to allow a run during combat." })

    ImGui.Spacing()
    local hudLabel = IconGlyphs.EyeOff .. " Hide HUD"
    if mod.hudHidden then hudLabel = IconGlyphs.Eye .. " Restore HUD" end
    if ImGui.Button(hudLabel, -1, 0) then HudUtils.Toggle(mod) end
end

local function DrawDebugPanel(mod, Core, HudUtils, CameraUtils)
    wu.Controls.ButtonRow({
        {
            label = IconGlyphs.Walk .. " Unlock Movement",
            tooltip = "Manually removes the Movement Lock status effect. Use if you are stuck in place.",
            onClick = function() CameraUtils.UnlockMovement(mod) end,
        },
        {
            label = IconGlyphs.Eye .. " Unlock Camera",
            tooltip = "Manually removes the Camera Lock status effect. Use if you cannot look around.",
            onClick = function() CameraUtils.UnlockCamera(mod) end,
        },
    }, { normalSpacing = true })
    wu.Controls.ButtonRow({
        {
            label = IconGlyphs.Eye .. " Force Restore HUD",
            tooltip = "Brings the HUD back even if the mod has lost track of hiding it. Use if the HUD stays hidden after a time-lapse.",
            onClick = function() HudUtils.ForceRestore(mod) end,
        },
        {
            label = IconGlyphs.Camera .. " Force Head Bob",
            tooltip = "Resets Additive Camera Motions to 1.0 (Full). Use if the camera feels too static.",
            onClick = function() CameraUtils.ForceRestore(mod) end,
        },
    }, { normalSpacing = true })
    wu.Controls.ButtonRow({
        {
            label = IconGlyphs.VolumeHigh .. " Restore Audio",
            tooltip = "Puts every volume this mod can mute back to full and gives the popups their sound back. Use if sound is still muted after a time-lapse.",
            onClick = function()
                AudioUtils.ForceRestore()
                Notifications.ForceRestore()
            end,
        },
    }, { normalSpacing = true })

    ImGui.Spacing()
    ImGui.Text(IconGlyphs.FileDocumentOutline .. " Log Level")
    local levelIndex = 0
    for i, name in ipairs(Log.LEVELS) do
        if name == mod.settings.logLevel then levelIndex = i - 1 end
    end
    ImGui.SetNextItemWidth(-1)
    local newIndex, levelChanged = ImGui.Combo("##LogLevel", levelIndex, Log.LEVELS, #Log.LEVELS)
    if levelChanged then
        mod.settings.logLevel = Log.LEVELS[newIndex + 1]
        Log.SetLevel(mod.settings.logLevel)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip("What the mod writes to the CET console and its log file.\nWarn shows only problems. Info adds start and stop stats. Debug adds everything.")
    end

    ImGui.Spacing()
    if mod.lastRunStats.valid then
        ImGui.Text(string.format("Speed setting      %.1fx", mod.lastRunStats.speedSetting))
        ImGui.Text(string.format("Real duration      %.2fs", mod.lastRunStats.durationReal))
        ImGui.Text(string.format("Game time passed   %s", Core.FormatDuration(mod.lastRunStats.timePassedGame)))
        ImGui.Text(string.format("Game time expected %s", Core.FormatDuration(mod.lastRunStats.timeExpectedGame)))
        ImGui.Spacing()
        ImGui.PushTextWrapPos(0.0)
        if mod.lastRunStats.mode == 0 then
            ImGui.TextDisabled(
                "Day Curve Match is the game time gained against the vanilla day curve. A mod that changes the length of the day moves it away from 100%, and a run of a few seconds reads rough because game time is counted in whole seconds.")
        else
            ImGui.TextDisabled(
                "Clock Efficiency is how closely the clock moved at the speed asked for. Below 100% means the script could not keep up.")
        end
        ImGui.PopTextWrapPos()
    else
        ImGui.TextDisabled("No run recorded yet.")
    end

    ImGui.Spacing()
    local verStr = mod.version
    local verWidth = ImGui.CalcTextSize(verStr)
    local availW = ImGui.GetContentRegionAvail()
    ImGui.SetCursorPosX(ImGui.GetCursorPosX() + availW - verWidth); ImGui.TextDisabled(verStr)
end

-- =================================================================
-- ### STATUS AND FOOTER ###
-- =================================================================

local function DrawStatusLine(mod)
    if mod.isActive then
        ImGui.TextColored(0, 1, 0, 1, IconGlyphs.PlayCircleOutline .. " RUNNING")
        ImGui.SameLine()
        if mod.settings.duration > 0 then
            ImGui.Text(string.format("| %.1fs of %.1fs", mod.elapsedTime, mod.settings.duration))
            wu.Controls.ProgressBar(mod.elapsedTime / mod.settings.duration, -1, 4)
        else
            ImGui.Text(string.format("| %.1fs, no end set", mod.elapsedTime))
        end
    elseif mod.isDelaying then
        ImGui.TextColored(1, 1, 0, 1,
            IconGlyphs.TimerSand .. " STARTING IN " .. string.format("%.1f", mod.delayTimer) .. "s")
    else
        ImGui.TextColored(1, 1, 0, 1, IconGlyphs.StopCircleOutline .. " READY")
    end
end

--- The last run's outcome in one line. The full numbers are in the Debug panel.
local function DrawLastRun(mod, Core)
    if not mod.lastRunStats.valid then return end

    ImGui.TextDisabled(string.format("Last run: %.1fs real, %s game",
        mod.lastRunStats.durationReal, Core.FormatDuration(mod.lastRunStats.timePassedGame)))
    ImGui.SameLine()

    local f = mod.lastRunStats.factor
    if f then
        local col = { 0, 1, 0, 1 }
        if math.abs(f - 1) > 0.02 then col = { 1, 1, 0, 1 } end
        if math.abs(f - 1) > 0.1 then col = { 1, 0.5, 0, 1 } end
        ImGui.TextColored(col[1], col[2], col[3], col[4], string.format("%.1f%%", f * 100))
    else
        ImGui.TextDisabled("n/a")
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(mod.lastRunStats.mode == 0 and "Day curve match" or "Clock efficiency")
    end
end

local function DrawFooter(mod, Core, HudUtils)
    local footerTop = ImGui.GetCursorPosY()
    local estData = Core.GetEstimatedData(mod)

    ImGui.Separator()
    ImGui.Text("Now " .. Core.GetGameTimeStr()); ImGui.SameLine()
    ImGui.Text("to"); ImGui.SameLine()
    ImGui.TextColored(0, 1, 1, 1, estData.endTime)
    if mod.settings.mode == 0 and ImGui.IsItemHovered() then
        ImGui.SetTooltip("The game clock runs slower around dawn and dusk. The estimate uses the vanilla day curve,\nso a mod that changes the length of the day makes it inaccurate.")
    end
    ImGui.SameLine()
    ImGui.TextDisabled("(" .. estData.durStr .. ")")

    if mod.settings.useStartTime then
        ImGui.TextDisabled("Starts at " .. estData.startTimeStr)
    end

    DrawLastRun(mod, Core)

    ImGui.Spacing()
    if mod.isActive or mod.isDelaying then
        if ImGui.Button(IconGlyphs.Stop .. " STOP", -1, 0) then Core.Stop(mod, HudUtils) end
    else
        if ImGui.Button(IconGlyphs.Play .. " START", -1, 0) then Core.Start(mod, HudUtils) end
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
        ImGui.Spacing()

        if wu.Controls.BeginFillChild("Body", { footerHeight = footerHeight, border = true }) then
            Section("ShotPanel", IconGlyphs.MovieRoll .. " Shot", true,
                function() DrawShotPanel(mod, Core, binding, spacing) end)
            Section("ScenePanel", IconGlyphs.CityVariantOutline .. " Scene", false,
                function() DrawScenePanel(mod, binding) end)
            Section("AudioPanel", IconGlyphs.VolumeHigh .. " Audio", false,
                function() DrawAudioPanel(mod, binding) end)
            Section("PlayerPanel", IconGlyphs.LockOutline .. " Player and HUD", false,
                function() DrawPlayerPanel(mod, HudUtils, binding) end)
            Section("DebugPanel", IconGlyphs.Bug .. " Debug", false,
                function() DrawDebugPanel(mod, Core, HudUtils, CameraUtils) end)
        end
        wu.Controls.EndFillChild("Body")

        DrawFooter(mod, Core, HudUtils)
    end
    wu.End()
end

return UI
