-- ======================================================================================
-- Simple Time-lapse - XUtilsFx Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- The optional features that run through CyanideX's XUtils: a lens with depth of field,
-- a weather sequence across the run, cinematic bars and fades. Every one is skipped
-- when XUtils is not installed, and every change records its own undo.
--
-- Depth of field exists only inside an XUtils camera session. The session starts at
-- the player's view with playerMode "none", which applies none of XUtils' own locks,
-- and its free-fly input is paused so the camera holds still for the run.
--
-- The bars and the fade sit on the HUD layer's window beside its Root canvas, so the
-- HUD hide leaves them on screen.
-- ======================================================================================

local Log = require("Modules/Log")
local Undo = require("Modules/Undo")
local Cron = require("Modules/Cron")

local XUtilsFx = {}

local MOD_ID = "SimpleTimelapse"

XUtilsFx.DOF_MODES = { "far", "near", "both" }
XUtilsFx.DOF_MODE_LABELS = { "Far only", "Near only", "Near and far" }
XUtilsFx.FOCUS_CURVES = { "Sine", "Quadratic", "Cubic", "Smoothstep", "Circular", "Exponential" }
XUtilsFx.BAR_RATIOS = { 2.39, 2.00, 1.85 }
XUtilsFx.BAR_LABELS = { "2.39:1", "2.00:1", "1.85:1" }
XUtilsFx.WEATHER_MODES = { "Even split", "Percent per state", "Game hours per state" }

-- Named lenses. Each sets the look sliders; focus behaviour is left as the player set it.
XUtilsFx.LENS_PRESETS = {
    { name = "Natural",   focalLength = 35.0,  fstop = 8.0, intensity = 1.0 },
    { name = "Street",    focalLength = 28.0,  fstop = 4.0, intensity = 1.0 },
    { name = "Portrait",  focalLength = 85.0,  fstop = 1.8, intensity = 1.5 },
    { name = "Telephoto", focalLength = 200.0, fstop = 2.8, intensity = 1.5 },
    { name = "Dreamy",    focalLength = 50.0,  fstop = 1.2, intensity = 2.5 },
}

local handle = nil

-- The weather schedule of the run in progress: segments, the one applied, and how
-- progress is measured.
local weatherRun = nil

-- True once a timed run has started its closing fade.
local fadingOut = false

local function XUtils()
    return GetMod("XUtils")
end

--- True when XUtils is installed and loaded.
function XUtilsFx.IsAvailable()
    local x = XUtils()
    return x ~= nil and x.Subscribe ~= nil
end

local function Handle()
    if handle then return handle end
    local x = XUtils()
    if not x then return nil end
    local ok, h = pcall(x.Subscribe, MOD_ID)
    if ok and h then handle = h end
    return handle
end

local function CameraSystem()
    local container = Game.GetScriptableSystemsContainer()
    if not container then return nil end
    return container:Get(CName.new("XUtils.XUtilsCameraSystem"))
end

local function VisualUtils()
    local x = XUtils()
    return x and x.visual and x.visual.VisualUtils or nil
end

-- =================================================================
-- ### WEATHER STATES ###
-- =================================================================

--- Every weather state the current environment offers, as { id, label } pairs.
function XUtilsFx.WeatherStates()
    local x = XUtils()
    if not x or not x.Weather then return {} end
    local ok, states = pcall(x.Weather.getValidStates)
    if not ok or type(states) ~= "table" then return {} end
    local out = {}
    for i, id in ipairs(states) do
        out[i] = { id = id, label = x.Weather.toDisplayName(id) }
    end
    return out
end

--- Drops entries a hand-edited or stale settings file could carry.
function XUtilsFx.SanitizeWeatherList(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, entry in ipairs(list) do
        if type(entry) == "table" and type(entry.state) == "string" then
            out[#out + 1] = {
                state = entry.state,
                percent = type(entry.percent) == "number" and math.max(1, math.min(entry.percent, 100)) or 50,
                hours = type(entry.hours) == "number" and math.max(0.25, math.min(entry.hours, 24)) or 1.0,
            }
        end
    end
    return out
end

--- Splits the run into one segment per state. Even and percent segments are fractions of
--- the run's length; hour segments are game seconds from the run's start.
local function BuildSchedule(s)
    local list = XUtilsFx.SanitizeWeatherList(s.xuWeatherList)
    if #list == 0 then return nil end

    local segments = {}
    if s.xuWeatherMode == 2 then
        local at = 0
        for i, entry in ipairs(list) do
            segments[i] = { state = entry.state, from = at }
            at = at + entry.hours * 3600
        end
        return { segments = segments, byGameTime = true, index = 0 }
    end

    local total = 0
    for _, entry in ipairs(list) do
        total = total + (s.xuWeatherMode == 1 and entry.percent or 1)
    end
    local at = 0
    for i, entry in ipairs(list) do
        segments[i] = { state = entry.state, from = at / total }
        at = at + (s.xuWeatherMode == 1 and entry.percent or 1)
    end
    return { segments = segments, byGameTime = false, index = 0 }
end

local function ApplyWeatherSegment(mod, index)
    local x = XUtils()
    local segment = weatherRun.segments[index]
    weatherRun.index = index
    local ok = x.Weather.setState(segment.state, mod.settings.xuWeatherBlend)
    Log.Debug("Weather %d of %d: %s (%s)", index, #weatherRun.segments, segment.state, tostring(ok))
end

-- =================================================================
-- ### START ###
-- =================================================================

local function StartLens(mod)
    local s = mod.settings
    local h = Handle()
    if not h then
        Log.Warn("XUtils did not accept a subscription, the lens is skipped")
        return
    end

    local started = h:StartCamera({
        playerMode = "none",
        showHints = false,
        showOverlay = false,
        showMinimap = false,
        blendTime = 0,
        lens = {
            dofMode = XUtilsFx.DOF_MODES[s.xuDofMode + 1] or "both",
            focalLength = s.xuFocalLength,
            fstop = s.xuFstop,
            intensity = s.xuDofIntensity,
            fovEnabled = s.xuZoomWithLens,
            autofocus = s.xuAutofocus,
            focalDist = s.xuFocusDist,
            autofocusMaxRange = s.xuFocusRange,
            afTransitionDuration = s.xuFocusSpeed,
            afCurve = XUtilsFx.FOCUS_CURVES[s.xuFocusCurve + 1] or "Sine",
        },
    })
    if started ~= true then
        Log.Warn("The XUtils camera did not start (%s), the lens is skipped. Another mod may own it",
            tostring(started))
        return
    end

    local sys = CameraSystem()
    if sys then sys:SetInputPaused(true) end

    Undo.Push("lens", function()
        local cameraSystem = CameraSystem()
        if cameraSystem then cameraSystem:SetInputPaused(false) end
        h:StopCamera({ blendTime = 0 })
    end)
end

local function StartWeather(mod)
    local x = XUtils()
    if not x.Weather then return end
    weatherRun = BuildSchedule(mod.settings)
    if not weatherRun then return end
    weatherRun.startGameSeconds = mod.startGameTime

    ApplyWeatherSegment(mod, 1)
    Undo.Push("weather", function()
        weatherRun = nil
        x.Weather.resetToNatural()
    end)
end

local function StartBars(mod)
    local vu = VisualUtils()
    if not vu then return end
    vu.NativeShowBars({
        aspectRatio = XUtilsFx.BAR_RATIOS[mod.settings.xuBarsRatio + 1] or 2.39,
        fadeDuration = 1.0,
        animationMode = "expand",
    })
    Undo.Push("bars", function() vu.NativeHideBars({ fadeDuration = 0.5 }) end)
end

local function StartFadeIn(mod)
    local x = XUtils()
    if not x.Effects then return end
    local duration = mod.settings.xuFadeInTime
    x.Effects.FadeOut(0)
    Cron.After(0.1, function() x.Effects.FadeIn(duration) end)
end

--- Records the undo that lifts a closing fade. Pushed before every other change of the
--- run, so it runs last: the view comes back after everything else is restored.
function XUtilsFx.PushFadeUndo(mod)
    fadingOut = false
    if not XUtilsFx.IsAvailable() or not mod.settings.xuFadeOut then return end
    Undo.Push("fadeOut", function()
        if not fadingOut then return end
        fadingOut = false
        local x = XUtils()
        if x and x.Effects then x.Effects.FadeIn(0.75) end
    end)
end

--- Applies every XUtils feature the settings ask for. Call inside the run's start.
function XUtilsFx.Start(mod)
    if not XUtilsFx.IsAvailable() then return end
    local s = mod.settings
    if s.xuLens then StartLens(mod) end
    if s.xuWeather then StartWeather(mod) end
    if s.xuBars then StartBars(mod) end
    if s.xuFadeIn then StartFadeIn(mod) end
end

-- =================================================================
-- ### UPDATE ###
-- =================================================================

--- Moves the weather to the segment the run has reached, and starts the closing fade
--- when a timed run is that close to its end.
function XUtilsFx.Update(mod, currentGameSeconds)
    if weatherRun then
        local progress
        if weatherRun.byGameTime then
            progress = currentGameSeconds - weatherRun.startGameSeconds
        elseif mod.settings.duration > 0 then
            progress = mod.elapsedTime / mod.settings.duration
        end
        if progress then
            local target = 1
            for i, segment in ipairs(weatherRun.segments) do
                if progress >= segment.from then target = i end
            end
            if target ~= weatherRun.index then ApplyWeatherSegment(mod, target) end
        end
    end

    if Undo.Has("fadeOut") and not fadingOut and mod.settings.duration > 0 then
        local remaining = mod.settings.duration - mod.elapsedTime
        if remaining <= mod.settings.xuFadeOutTime then
            local x = XUtils()
            if x and x.Effects then
                fadingOut = true
                x.Effects.FadeOut(math.max(remaining, 0.1))
            end
        end
    end
end

-- =================================================================
-- ### LENS PRESETS ###
-- =================================================================

--- The preset whose look matches the settings, or nil.
function XUtilsFx.MatchingPreset(s)
    for _, preset in ipairs(XUtilsFx.LENS_PRESETS) do
        if math.abs(s.xuFocalLength - preset.focalLength) < 0.05 and math.abs(s.xuFstop - preset.fstop) < 0.05
            and math.abs(s.xuDofIntensity - preset.intensity) < 0.05 then
            return preset.name
        end
    end
    return nil
end

function XUtilsFx.ApplyPreset(mod, preset)
    mod.settings.xuFocalLength = preset.focalLength
    mod.settings.xuFstop = preset.fstop
    mod.settings.xuDofIntensity = preset.intensity
end

return XUtilsFx
