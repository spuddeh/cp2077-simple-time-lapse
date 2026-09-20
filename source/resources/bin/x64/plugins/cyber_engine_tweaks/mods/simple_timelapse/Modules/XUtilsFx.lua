-- ======================================================================================
-- Simple Time-lapse - XUtilsFx Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- The optional features that run through CyanideX's XUtils: a camera with shake and a
-- lens with depth of field, a weather sequence across the run, cinematic bars and fades.
-- Every one is skipped when XUtils is not installed, and every change records its own undo.
--
-- The camera is an XUtils session, detached from the player rather than following V. It
-- starts at the player's view, and the camera mode decides what happens next: Static
-- pauses the free-fly input so the frame holds still, and leaves the locks to this mod's
-- own settings. Free fly gives the input to XUtils, which then owns the restrictions, and
-- brings V along whenever the camera pulls 30 m clear so the world keeps streaming.
--
-- Depth of field exists only inside that session, so asking for the lens asks for the
-- camera. The camera without the lens moves the shot and leaves the picture alone.
--
-- Shake reaches a static camera only. XUtils applies a shake on its playback, timeline
-- and point cloud paths, and the free-fly path writes the camera itself every frame, so
-- a shake written from here would be overwritten before it drew.
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
XUtilsFx.CAMERA_MODES = { "Static", "Free fly" }

-- Named lenses. Each sets the look sliders; focus behaviour is left as the player set it.
XUtilsFx.LENS_PRESETS = {
    { name = "Natural",   focalLength = 35.0,  fstop = 8.0, intensity = 1.0 },
    { name = "Street",    focalLength = 28.0,  fstop = 4.0, intensity = 1.0 },
    { name = "Portrait",  focalLength = 85.0,  fstop = 1.8, intensity = 1.5 },
    { name = "Telephoto", focalLength = 200.0, fstop = 2.8, intensity = 1.5 },
    { name = "Dreamy",    focalLength = 50.0,  fstop = 1.2, intensity = 2.5 },
}

local handle = nil

-- The shake of the run in progress, and the parked transform it displaces. Only a
-- static camera has one: see XUtilsFx.ShakeReachesCamera.
local shake = nil
local shakeBase = nil

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

--- True when the run takes over the camera. Depth of field needs the session, so it
--- turns the camera on with it.
function XUtilsFx.UsesCamera(s)
    return XUtilsFx.IsAvailable() and (s.xuCamera or s.xuLens)
end

--- True when the run will fly the camera rather than park it. The player's own
--- movement and camera locks do nothing in that case: XUtils owns the input.
function XUtilsFx.IsFreeFly(s)
    return XUtilsFx.UsesCamera(s) and s.xuCameraMode == 1
end

--- Shake reaches a parked camera only. XUtils applies a shake on its playback, timeline
--- and point cloud paths; the free-fly path rewrites the camera every frame instead, so
--- there is no frame in which a shake written from here would survive.
function XUtilsFx.ShakeReachesCamera(s)
    return XUtilsFx.UsesCamera(s) and s.xuCameraMode == 0
end

--- The shake recipes XUtils ships, newest read each call so a user preset shows up.
function XUtilsFx.ShakePresets()
    local x = XUtils()
    if not x or not x.CameraShake then return {} end
    local ok, names = pcall(x.CameraShake.GetPresetNames)
    if not ok or type(names) ~= "table" then return {} end
    return names
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

--- The session's camera entity. XUtils keeps its Camera module to itself - only
--- CameraController, CameraShake and CameraLens are on the mod table - so the transform
--- is reached through the scriptable system instead.
---
--- Ready, not spawned: Spawn sets the spawned flag on the call that requests the entity,
--- and the entity resolves some frames later. Until it does, the camera reports a position
--- of 0, 0, 0, which reads as a real answer rather than a missing one.
local function RedCamera()
    local sys = CameraSystem()
    if not sys then return nil end
    local cam = sys:GetCamera()
    if not cam or not cam:IsSpawned() or not cam:IsReady() then return nil end
    return cam
end

--- The camera's place, as position and rotation tables. Nil until the entity is there.
local function ReadTransform()
    local cam = RedCamera()
    if not cam then return nil end
    local str = cam:GetTransformString()
    if not str or str == "" then return nil end
    local parts = {}
    for part in string.gmatch(str, "[^;]+") do parts[#parts + 1] = tonumber(part) end
    if #parts < 6 then return nil end
    -- The origin is what an unresolved entity reports, and no shot is taken from it.
    if parts[1] == 0 and parts[2] == 0 and parts[3] == 0 then return nil end
    return {
        position = { x = parts[1], y = parts[2], z = parts[3] },
        rotation = { yaw = parts[4], pitch = parts[5], roll = parts[6] },
    }
end

-- How far a shake may carry the camera from where the shot is parked, in metres.
local SHAKE_REACH = 3.0

--- False for a point further than a shake can honestly reach, and for one that is not a
--- number at all, which is how a divide by zero arrives from the other side.
local function Near(point, base)
    local dx, dy, dz = point.x - base.x, point.y - base.y, point.z - base.z
    local distanceSq = dx * dx + dy * dy + dz * dz
    if distanceSq ~= distanceSq then return false end
    return distanceSq <= SHAKE_REACH * SHAKE_REACH
end

local function WriteTransform(position, rotation)
    local cam = RedCamera()
    if not cam then return end
    cam:SetTransform(position.x, position.y, position.z, rotation.yaw, rotation.pitch, rotation.roll)
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

-- Sensitivity has no absolute setter: Adjust takes a number of steps, and a step is 0.1.
local SENSITIVITY_STEP = 0.1

--- Hands the free-fly keys to the run. The slots name XUtils' own actions and read their
--- keys from XUtils' hotkey system, so a key the player rebound in Mod Settings is the key
--- that works here. StopCamera clears the active mode and the handlers with the session.
local function RegisterFlyKeys()
    local x = XUtils()
    local cc, ff = x and x.CameraController, x and x.FreeFlyController
    if not cc or not ff or not cc.registerControlMode then return end

    -- A held slot sets and clears one of the free-fly keys by name, so the numbers behind
    -- those names stay XUtils' business.
    local function Hold(...)
        local names = { ... }
        return function(down)
            return function()
                for _, name in ipairs(names) do ff.setKeyState(name, down) end
            end
        end
    end
    local precision = Hold("precision", "slow")
    local rollLeft = Hold("rollLeft")
    local rollRight = Hold("rollRight")

    cc.registerControlMode(MOD_ID, "timelapse", {
        title = "Time-lapse",
        scriptableSystemName = "XUtils.XUtilsFreeFlyHotkeys",
        slots = {
            -- Precision holds slow as well, which is what makes the fine move fine.
            { action = "XU_FreeFly_Precision", label = "Precision",
              onPress = precision(true), onRelease = precision(false) },
            { action = "XU_FreeFly_RollLeft", label = "Roll L",
              onPress = rollLeft(true), onRelease = rollLeft(false) },
            { action = "XU_FreeFly_RollRight", label = "Roll R",
              onPress = rollRight(true), onRelease = rollRight(false) },
            { action = "XU_FreeFly_Roll", label = "Roll",
              onScroll = ff.adjustRoll, onMiddle = ff.resetRoll },
            { action = "XU_FreeFly_FOV", label = "FOV",
              onScroll = ff.adjustFOV, onMiddle = ff.resetFOV },
            { action = "XU_FreeFly_Sensitivity", label = "Sensitivity",
              onScroll = ff.adjustSensitivity, onMiddle = ff.resetSensitivity },
        },
        defaultScroll = ff.adjustSpeed,
        defaultScrollLabel = "Speed",
    })
    cc.setActiveControlMode(MOD_ID, "timelapse")
    Log.Debug("Free-fly keys registered")
end

--- Applies the free-fly feel settings to the session that has just started.
local function ApplyFlyFeel(mod)
    local s = mod.settings
    local x = XUtils()
    local ff = x and x.FreeFlyController
    if not ff then return end

    ff.resetSensitivity()
    local current = ff.getSensitivity() or 1.0
    if math.abs(s.xuLookSensitivity - current) > 0.001 then
        ff.adjustSensitivity((s.xuLookSensitivity - current) / SENSITIVITY_STEP)
    end

    ff.setRoll(s.xuRoll)
    ff.setPitchUnlocked(s.xuPitchUnlocked)

    Log.Debug("Fly feel: look sensitivity asked %.2f, got %s; roll %.1f; pitch unlocked %s",
        s.xuLookSensitivity, tostring(ff.getSensitivity()), s.xuRoll, tostring(s.xuPitchUnlocked))
end

--- Takes over a static camera's transform for the run: the roll it is held at, and the
--- shake laid over it. Nothing else writes that camera, because a paused free-fly input
--- skips the update that would. The base is read on the first frame it can be, since the
--- camera entity spawns after the session starts.
local function StartStaticCamera(mod)
    local s = mod.settings
    local wantShake = s.xuShake
    local wantRoll = math.abs(s.xuRoll) > 0.001
    if not wantShake and not wantRoll then return end

    local instance = nil
    if wantShake then
        local x = XUtils()
        local ok, built = pcall(x.CameraShake.new)
        if not ok or not built then
            Log.Warn("The camera shake did not start (%s)", tostring(built))
        else
            if s.xuShakePreset ~= "" then built:LoadPreset(s.xuShakePreset) end
            built:Reconfigure({ intensity = s.xuShakeIntensity })
            built:Start()
            instance = built
        end
    end

    shake = instance
    shakeBase = nil
    Log.Debug("Static camera taken over: shake %s, roll %.1f",
        instance and s.xuShakePreset or "off", s.xuRoll)

    Undo.Push("staticCamera", function()
        local base, current = shakeBase, shake
        shake, shakeBase = nil, nil
        if current then
            current:Stop()
            current:Destroy()
        end
        -- Put the camera back where it was found, before the session's undo stops it.
        if base then WriteTransform(base.position, base.rotation) end
    end)
end

local function StartCamera(mod)
    local s = mod.settings
    local h = Handle()
    if not h then
        Log.Warn("XUtils did not accept a subscription, the camera is skipped")
        return
    end

    local freeFly = s.xuCameraMode == 1

    local config = {
        -- V is hidden either way: the camera renders from outside the body, and the
        -- first-person mesh has no head.
        -- Static applies none of XUtils' own locks, so this mod's Hold the shot
        -- settings still decide what the player may do. Free fly hands input to XUtils,
        -- so XUtils also takes the restrictions.
        playerMode = freeFly and { invisible = true, restrictions = true } or { invisible = true },
        showHints = false,
        showOverlay = false,
        showMinimap = false,
        blendTime = 0,
    }

    -- The session is what depth of field needs; without it the camera moves and the
    -- picture is left alone.
    if s.xuLens then
        config.lens = {
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
        }
    end

    if freeFly then
        -- V is brought along only once the camera is 30 m clear, so the world keeps
        -- streaming without V being slid under it every frame, which sounds like
        -- footsteps. The hidden body has its visual components toggled off, not its
        -- audio, so anything that moves V is heard.
        config.proximityTeleport = { enabled = true, delay = 2.0, interval = 2.5, distance = 30.0 }
        config.freeFly = {
            baseSpeed = s.xuFlySpeed,
            movementMode = s.xuFlyLevel and "global" or "relative",
        }
    end

    local started = h:StartCamera(config)
    if started ~= true then
        Log.Warn("The XUtils camera did not start (%s), and is skipped. Another mod may own it",
            tostring(started))
        return
    end

    if freeFly then
        ApplyFlyFeel(mod)
        RegisterFlyKeys()
    else
        local sys = CameraSystem()
        if sys then sys:SetInputPaused(true) end
    end

    -- Pushed after the shake, so the shake puts the camera back before the session ends.
    Undo.Push("camera", function()
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
    if XUtilsFx.UsesCamera(s) then
        StartCamera(mod)
        if XUtilsFx.ShakeReachesCamera(s) then StartStaticCamera(mod) end
    end
    if s.xuWeather then StartWeather(mod) end
    if s.xuBars then StartBars(mod) end
    if s.xuFadeIn then StartFadeIn(mod) end
end

-- =================================================================
-- ### UPDATE ###
-- =================================================================

--- Moves the weather to the segment the run has reached, and starts the closing fade
--- when a timed run is that close to its end.
function XUtilsFx.Update(mod, currentGameSeconds, delta)
    if Undo.Has("staticCamera") then
        -- The camera entity spawns a frame or two after the session starts, so the place
        -- it is held at is whatever the first readable frame reports.
        if not shakeBase then
            shakeBase = ReadTransform()
            if shakeBase then
                Log.Debug("Static camera base read at %.2f, %.2f, %.2f",
                    shakeBase.position.x, shakeBase.position.y, shakeBase.position.z)
            end
        end

        if shakeBase then
            local held = {
                yaw = shakeBase.rotation.yaw,
                pitch = shakeBase.rotation.pitch,
                roll = mod.settings.xuRoll,
            }
            if shake then
                local position, rotation = shake:Apply(shakeBase.position, held, { delta = delta })
                -- A shake is a displacement of a few centimetres. Anything that moves the
                -- camera metres from where it is parked is not a shake, and holding the
                -- frame is a better answer than following it.
                if position and rotation and Near(position, shakeBase.position) then
                    WriteTransform(position, rotation)
                else
                    WriteTransform(shakeBase.position, held)
                end
            else
                WriteTransform(shakeBase.position, held)
            end
        end
    end

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
