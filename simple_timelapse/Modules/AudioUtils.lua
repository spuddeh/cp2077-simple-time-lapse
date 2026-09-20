-- ======================================================================================
-- Simple Time-lapse - AudioUtils Module
-- Mod Version: 2.0.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Turns volume sliders down to 0 for the length of a run. Each slider records its own
-- undo, which puts the level back only if the slider is still at 0, so a level changed
-- during the run belongs to whoever changed it.
-- ======================================================================================

local GameSettings = require("Modules/GameSettings")
local Log = require("Modules/Log")
local Undo = require("Modules/Undo")

local AudioUtils = {}

-- Each setting a checkbox mutes. The radio plays through two sliders: the Radioport on
-- foot and the car radio in a vehicle.
local GROUPS = {
    muteRadio = { "/audio/volume/RadioportVolume", "/audio/volume/CarRadioVolume" },
    muteMusic = { "/audio/volume/MusicVolume" },
    muteSfx = { "/audio/volume/SfxVolume" },
}

-- The level a panic restore picks, because a lost run's levels cannot be read back.
local PANIC_LEVEL = 100

local function MutePath(path)
    local ok, before = pcall(function() return GameSettings.Get(path) end)
    if not ok or type(before) ~= "number" then
        Log.Warn("Could not read %s, left unchanged", path)
        return
    end
    if before == 0 then return end

    GameSettings.Set(path, 0)
    Log.Debug("Muted %s (was %d)", path, before)
    Undo.Push("audio:" .. path, function()
        if GameSettings.Get(path) == 0 then GameSettings.Set(path, before) end
    end)
end

--- Mutes every slider the run's settings ask for.
function AudioUtils.Mute(mod)
    for setting, paths in pairs(GROUPS) do
        if mod.settings[setting] then
            for _, path in ipairs(paths) do MutePath(path) end
        end
    end
end

--- Panic button: puts every slider this mod can mute back to full, whether or not the
--- mod muted it. For a level left at 0 by a crash mid-run.
function AudioUtils.ForceRestore()
    for _, paths in pairs(GROUPS) do
        for _, path in ipairs(paths) do
            pcall(function()
                if GameSettings.Get(path) == 0 then GameSettings.Set(path, PANIC_LEVEL) end
            end)
        end
    end
    Log.Debug("Audio levels forced back to %d", PANIC_LEVEL)
end

return AudioUtils
