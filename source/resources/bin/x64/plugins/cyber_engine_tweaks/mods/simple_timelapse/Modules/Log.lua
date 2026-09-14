-- ======================================================================================
-- Simple Time-lapse - Log Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Levelled logging. One setting decides what reaches the CET console and the mod's log.
-- ======================================================================================

local Log = {}

local PREFIX = "[Simple Time-lapse]"

-- Quietest first. A message is written when its level is at or below the setting,
-- so "Warn" writes errors and warnings and nothing else.
Log.LEVELS = { "Off", "Error", "Warn", "Info", "Debug" }

local LEVEL_VALUE = { Off = 0, Error = 1, Warn = 2, Info = 3, Debug = 4 }

-- A fresh install gets this level, and a normal session writes nothing at it.
Log.DEFAULT_LEVEL = "Warn"

local currentLevel = LEVEL_VALUE[Log.DEFAULT_LEVEL]

--- Sets the level by name. An unknown name falls back to the default rather than to Off,
--- so a bad value in settings.json cannot hide errors.
function Log.SetLevel(name)
    currentLevel = LEVEL_VALUE[name] or LEVEL_VALUE[Log.DEFAULT_LEVEL]
end

function Log.IsLevel(name)
    return LEVEL_VALUE[name] ~= nil
end

--- Formats only when there are arguments, so a gated call costs no string work.
local function Emit(tag, msg, ...)
    if select("#", ...) > 0 then msg = string.format(msg, ...) end
    local line = PREFIX .. " " .. tag .. tostring(msg)
    print(line)
    spdlog.info(line)
end

function Log.Error(msg, ...)
    if currentLevel >= LEVEL_VALUE.Error then Emit("[ERROR] ", msg, ...) end
end

function Log.Warn(msg, ...)
    if currentLevel >= LEVEL_VALUE.Warn then Emit("[WARN] ", msg, ...) end
end

function Log.Info(msg, ...)
    if currentLevel >= LEVEL_VALUE.Info then Emit("", msg, ...) end
end

function Log.Debug(msg, ...)
    if currentLevel >= LEVEL_VALUE.Debug then Emit("[DEBUG] ", msg, ...) end
end

return Log
