-- ======================================================================================
-- Simple Time-lapse - UI Module
-- Mod Version:  v1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Handles all rendering, including the Header/Body/Footer layout architecture.
-- The window and its controls come from Window Utils, a required dependency.
-- ======================================================================================

local Log = require("Modules/Log")
local Settings = require("Modules/Settings")
local AudioUtils = require("Modules/AudioUtils")

local UI = {}

local WINDOW_NAME = "Simple Time-lapse"

-- Choices for the Start Time combos. Index 0 is 1 o'clock and 00 minutes.
local HOURS = {}; for i = 1, 12 do HOURS[i] = tostring(i) end
local MINUTES = {}; for i = 0, 59 do MINUTES[i + 1] = string.format("%02d", i) end

local wu = nil
local binding = nil

-- Height of the Settings tab footer, measured each frame and used to size the body on the next.
local footerHeight = 200

--- Shown in place of the window when Window Utils is not installed.
local function DrawMissingDependency()
    if ImGui.Begin(WINDOW_NAME, ImGuiWindowFlags.AlwaysAutoResize) then
        ImGui.TextColored(1, 0.3, 0.3, 1, "Simple Time-lapse requires Window Utils.")
        ImGui.Text("Install it from Nexus Mods (mod 26589). The hotkeys still work without it.")
    end
    ImGui.End()
end

local function DrawSettingsTab(mod, Core, HudUtils, c, spacing)
    ImGui.Spacing()

    -- === BODY (SCROLLABLE) ===
    if wu.Controls.BeginFillChild("SettingsBody", { footerHeight = footerHeight, border = true }) then
        local bodyW = ImGui.GetContentRegionAvail()
        -- A run reads its mode and speeds once, at Start.
        local runLocked = mod.isActive

        -- 0. TIMELAPSE MODE
        ImGui.TextWrapped(IconGlyphs.MovieRoll .. " Time-lapse Mode")
        if runLocked then
            ImGui.TextDisabled("Mode and speed are locked while a time-lapse runs.")
        end
        ImGui.BeginDisabled(runLocked)
        if ImGui.RadioButton("Simulation (Standard)", mod.settings.mode == 0) then
            mod.settings.mode = 0
            Core.ClampSpeed(mod)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                "Speeds up the ENTIRE game simulation (NPCs, Physics, Time). \nBest for bustling city shots.")
        end
        ImGui.SameLine()
        if ImGui.RadioButton("Clock Only", mod.settings.mode == 1) then mod.settings.mode = 1 end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip(
                "Speeds up ONLY the Time of Day (Sun/Stars). \nNPCs and Traffic move at normal speed. \nBest for sunsets/sunrises.")
        end
        ImGui.EndDisabled()

        ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()

        -- 1. START TIME
        ImGui.TextWrapped(IconGlyphs.CalendarClock .. " Start Time")
        local comboW = (bodyW * 0.35) - spacing

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
        if ImGui.Button(IconGlyphs.DebugStepOver .. " Set Time From Dropdowns (Jump)", -1, 0) then
            Core.SetTimeNow(mod)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Immediately sets the in-game time to the selected Hour/Minute.")
        end

        ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()

        -- 2. START DELAY
        ImGui.TextWrapped(IconGlyphs.TimerOutline .. " Start Delay (Seconds)")
        c:SliderFloat(nil, "startDelay", 0.0, 30.0, {
            format = "%.1fs",
            tooltip = "Wait this many seconds after pressing Start before the time-lapse actually begins.",
        })

        ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()

        -- 3. SPEED
        ImGui.TextWrapped(IconGlyphs.Speedometer .. " Dilation Speed (Multiplier)")
        ImGui.BeginDisabled(runLocked)
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

        -- Precise Input (Visible only in Clock Mode)
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

        ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()

        -- 4. DURATION
        ImGui.TextWrapped(IconGlyphs.TimerSand .. " Duration")
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

        ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()

        -- 5. CONFIGURATION
        ImGui.TextWrapped(IconGlyphs.MovieCog .. " Configuration")

        local curX = 0
        local function check(label, varName, tooltip)
            local w = ImGui.CalcTextSize(label) + 40
            if curX + w > bodyW then curX = 0 else if curX > 0 then ImGui.SameLine() end end
            c:Checkbox(label, varName, { tooltip = tooltip })
            curX = curX + w + spacing
        end

        check(IconGlyphs.History .. " Set Time on Start", "useStartTime",
            "When time-lapse starts, instantly set game time to the Hour/Minute selected above.")
        if mod.settings.useStartTime then
            check(IconGlyphs.Restore .. " Restore Time on Stop", "restoreTime",
                "When time-lapse stops, sets the game time back to what it was before Start.")
        end
        check(IconGlyphs.MessageTextOutline .. " Messages", "showMessages",
            "Show status notifications on the left side of the screen.")
        check(IconGlyphs.VolumeHigh .. " Audio Cues", "playAudio", "Play sound effects for the countdown.")
        check(IconGlyphs.RadioOff .. " Mute Radio", "muteRadio",
            "Silences the Radioport and the car radio for the run, and puts both levels back on Stop.")
        check(IconGlyphs.MusicNoteOff .. " Mute Music", "muteMusic",
            "Silences the game's own score for the run.")
        check(IconGlyphs.VolumeOff .. " Mute Sound Effects", "muteSfx",
            "Silences sound effects for the run, city ambience and this mod's own cues included.\n" ..
            "Use it to keep a call or a message alert off a recording.")
        check(IconGlyphs.EyeOff .. " Auto-Hide HUD", "autoHideHud",
            "Hides the HUD and notifications when the time-lapse starts, and shows them again when it stops.\nThe Toggle HUD hotkey and the button below still work at any time.")
        check(IconGlyphs.CameraOutline .. " No Head Bob", "disableHeadBob",
            "Disables Additive Camera Motions (Head Bobbing) during time-lapse for a steady shot.")

        check(IconGlyphs.Walk .. " Lock Movement", "lockMovement",
            "Prevents player movement during time-lapse to avoid accidental shifts.")
        check(IconGlyphs.Eye .. " Lock Camera", "lockCamera",
            "Prevents camera rotation during time-lapse to ensure a static frame.")
        check(IconGlyphs.ShieldOutline .. " Block Start in Combat", "blockInCombat",
            "Refuses to start a time-lapse while you are in combat.\nUntick to allow a run during combat.")

        check(IconGlyphs.AirplaneOff .. " Disable Air Traffic", "disableAirTraffic",
            "Disables flying AVs/cars during time-lapse.\nNOTE: You may need to run the time-lapse for longer to clear out existing AVs")
        check(IconGlyphs.AccountGroupOutline .. " Disable Crowds & Traffic", "disableCrowds",
            "Disables ambient pedestrians and street vehicles during time-lapse.\nNOTE: You may need to run the time-lapse for longer to clear out existing traffic/NPCs")
        check(IconGlyphs.Speedometer .. " Traffic Frenzy Mode (Experimental)", "forceVehicleDilation",
            "Speeds up ambient traffic during Simulation mode via AI command injection.\n\n" ..
            "While active, the following overrides are applied:\n" ..
            " - Collision damage disabled (vehicles bounce instead of crumpling)\n" ..
            " - Overlapping vehicles auto-despawn to clear jams\n" ..
            " - Safety measures enabled with increased buffer distance\n" ..
            " - Faster despawn recycling to maintain traffic density\n\n" ..
            "Traffic smooths out the longer the time-lapse runs.\n\n" ..
            "EXPECT JANK: Cars may corner aggressively, briefly stop, or behave unusually.")

        if mod.settings.forceVehicleDilation then
            ImGui.Spacing()
            ImGui.TextWrapped(IconGlyphs.Speedometer .. " Vehicle Speed Multiplier")
            ImGui.BeginDisabled(runLocked)
            c:SliderFloat(nil, "frenzySpeedMult", 1.0, 20.0, {
                format = "%.1fx",
                tooltip = "Controls how fast traffic moves. Decoupled from time dilation speed.\n" ..
                    "1.5x looks best with 10x dilation. Higher values = faster but jankier.",
            })
            ImGui.EndDisabled()
        end

        -- Manual HUD Button
        ImGui.Spacing()
        local hudLabel = IconGlyphs.EyeOff .. " Hide HUD"
        if mod.hudHidden then hudLabel = IconGlyphs.Eye .. " Restore HUD" end

        if ImGui.Button(hudLabel, -1, 0) then HudUtils.Toggle(mod) end
    end
    wu.Controls.EndFillChild("SettingsBody")

    -- === FOOTER (PINNED) ===
    local footerTop = ImGui.GetCursorPosY()
    local estData = Core.GetEstimatedData(mod)

    ImGui.TextWrapped("Current Game Time: ")
    ImGui.SameLine(); ImGui.Text(Core.GetGameTimeStr())

    if mod.settings.useStartTime then
        ImGui.TextWrapped("Planned Start Time: ")
        ImGui.SameLine(); ImGui.Text(estData.startTimeStr)
    end

    ImGui.TextWrapped("Est. Game Time at End: ")
    ImGui.SameLine(); ImGui.TextColored(0, 1, 1, 1, estData.endTime)
    if mod.settings.mode == 0 and ImGui.IsItemHovered() then
        ImGui.SetTooltip("The game clock runs slower around dawn and dusk. The estimate uses the vanilla day curve,\nso a mod that changes the length of the day makes it inaccurate.")
    end

    ImGui.TextWrapped("Total Game Time Passed: ")
    ImGui.SameLine(); ImGui.TextColored(0, 1, 0, 1, estData.durStr)

    ImGui.Spacing()

    if mod.isActive or mod.isDelaying then
        if ImGui.Button(IconGlyphs.Stop .. " STOP", -1, 0) then Core.Stop(mod, HudUtils) end
    else
        if ImGui.Button(IconGlyphs.Play .. " START", -1, 0) then Core.Start(mod, HudUtils) end
    end

    footerHeight = ImGui.GetCursorPosY() - footerTop - ImGui.GetStyle().ItemSpacing.y
end

local function DrawDebugTab(mod, Core, HudUtils, CameraUtils)
    -- PANIC CONTROLS
    ImGui.Spacing()
    ImGui.TextWrapped(IconGlyphs.AlertOctagon .. " Panic Controls")
    ImGui.Spacing()

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
            label = IconGlyphs.VolumeHigh .. " Restore Audio",
            tooltip = "Puts every volume this mod can mute back to full. Use if sound is still muted after a time-lapse.",
            onClick = function() AudioUtils.ForceRestore() end,
        },
        {
            label = IconGlyphs.Camera .. " Force Head Bob",
            tooltip = "Resets Additive Camera Motions to 1.0 (Full). Use if the camera feels too static.",
            onClick = function() CameraUtils.ForceRestore(mod) end,
        },
    }, { normalSpacing = true })

    ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()
    ImGui.TextWrapped(IconGlyphs.FileDocumentOutline .. " Log Level")
    local levelIndex = 0
    for i, name in ipairs(Log.LEVELS) do
        if name == mod.settings.logLevel then levelIndex = i - 1 end
    end
    local newIndex, levelChanged = ImGui.Combo("##LogLevel", levelIndex, Log.LEVELS, #Log.LEVELS)
    if levelChanged then
        mod.settings.logLevel = Log.LEVELS[newIndex + 1]
        Log.SetLevel(mod.settings.logLevel)
    end
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip("What the mod writes to the CET console and its log file.\nWarn shows only problems. Info adds start and stop stats. Debug adds everything.")
    end

    ImGui.Spacing()
    ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()
    ImGui.TextWrapped(IconGlyphs.ChartBar .. " Last Run Statistics")
    if mod.lastRunStats.valid then
        ImGui.TextWrapped(string.format("Speed Setting:      %.1fx", mod.lastRunStats.speedSetting))
        ImGui.TextWrapped(string.format("Real Duration:      %.2fs", mod.lastRunStats.durationReal))
        ImGui.TextWrapped(string.format("Game Time Passed:   %.0fs", mod.lastRunStats.timePassedGame))
        ImGui.TextWrapped(string.format("Game Time Expected: %.0fs", mod.lastRunStats.timeExpectedGame))

        if mod.lastRunStats.mode == 0 then
            ImGui.Spacing(); ImGui.TextWrapped("Day Curve Match:"); ImGui.SameLine()
            local f = mod.lastRunStats.factor or 1; local col = { 0, 1, 0, 1 }
            if math.abs(f - 1) > 0.02 then col = { 1, 1, 0, 1 } end; if math.abs(f - 1) > 0.1 then col = { 1, 0.5, 0, 1 } end
            if mod.lastRunStats.factor then
                ImGui.TextColored(col[1], col[2], col[3], col[4], string.format("%.1f%%", f * 100))
            else
                ImGui.TextDisabled("n/a")
            end
            ImGui.Spacing(); ImGui.PushTextWrapPos(0.0)
            ImGui.TextDisabled(
                "Note: The game clock gains 8 game seconds per simulated second, slowed to about 72% around dawn and dusk. 100% means the run matched the vanilla day curve built into the mod. A mod that changes the length of the day moves this away from 100%, and runs under a few seconds read rough because game time is counted in whole seconds.")
            ImGui.PopTextWrapPos()
        else
            -- Mode 1: Efficiency (Target ~1.0)
            ImGui.Spacing(); ImGui.TextWrapped("Clock Efficiency:"); ImGui.SameLine()
            local f = mod.lastRunStats.factor or 1; local col = { 0, 1, 0, 1 }
            if f < 0.95 then col = { 1, 1, 0, 1 } end; if f < 0.5 then col = { 1, 0.5, 0, 1 } end
            if mod.lastRunStats.factor then
                ImGui.TextColored(col[1], col[2], col[3], col[4], string.format("%.2f%%", f * 100))
            else
                ImGui.TextDisabled("n/a")
            end
            ImGui.Spacing(); ImGui.PushTextWrapPos(0.0)
            ImGui.TextDisabled(
                "Note: 100% means the clock moved exactly as fast as requested. Lower values mean the script couldn't keep up (unlikely).")
            ImGui.PopTextWrapPos()
        end
    else
        ImGui.PushTextWrapPos(0.0)
        ImGui.TextDisabled("No data available yet. Run the time-lapse to generate stats.")
        ImGui.PopTextWrapPos()
    end

    ImGui.Spacing(); ImGui.Separator(); ImGui.Spacing()
    local verStr = mod.version
    local verWidth = ImGui.CalcTextSize(verStr)
    local availW = ImGui.GetContentRegionAvail()
    ImGui.SetCursorPosX(ImGui.GetCursorPosX() + availW - verWidth); ImGui.TextDisabled(verStr)
end

function UI.Draw(mod, Core, HudUtils, CameraUtils)
    if not mod.isOverlayOpen then return end

    wu = wu or GetMod("WindowUtils")
    if not wu then
        DrawMissingDependency()
        return
    end
    binding = binding or wu.Controls.bind(mod.settings, mod.defaults, function() Settings.Save(mod) end)

    wu.SetConstraints(700, 960, 4000, 4000, WINDOW_NAME)
    ImGui.SetNextWindowSize(700, 960, ImGuiCond.FirstUseEver)

    -- First return is the title-bar close button, second is visibility (false while collapsed).
    local open, visible = wu.Begin(WINDOW_NAME, true)
    if not open then
        -- Hidden until the CET overlay next opens.
        mod.isOverlayOpen = false
    end

    if visible then
        local spacing = ImGui.GetStyle().ItemSpacing.x

        -- === HEADER (Pinned) ===
        if mod.isActive then
            ImGui.TextColored(0, 1, 0, 1, IconGlyphs.PlayCircleOutline .. " RUNNING")
            ImGui.SameLine(); ImGui.Text(string.format("| %.2fs / %.2fs", mod.elapsedTime, mod.settings.duration))
        elseif mod.isDelaying then
            ImGui.TextColored(1, 1, 0, 1,
                IconGlyphs.TimerSand .. " STARTING IN " .. string.format("%.1f", mod.delayTimer) .. "s")
        else
            ImGui.TextColored(1, 1, 0, 1, IconGlyphs.StopCircleOutline .. " READY")
        end

        if ImGui.BeginTabBar("MainTabs") then
            if ImGui.BeginTabItem(" " .. IconGlyphs.Cog .. " Settings ") then
                DrawSettingsTab(mod, Core, HudUtils, binding, spacing)
                ImGui.EndTabItem()
            end

            if ImGui.BeginTabItem(" " .. IconGlyphs.Bug .. " Debug ") then
                DrawDebugTab(mod, Core, HudUtils, CameraUtils)
                ImGui.EndTabItem()
            end
            ImGui.EndTabBar()
        end
    end
    wu.End()
end

return UI
