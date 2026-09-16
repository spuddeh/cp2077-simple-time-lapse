-- ======================================================================================
-- Simple Time-lapse - Settings Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Saves and loads the player's settings to settings.json in the mod folder.
-- Debug and experimental options are never saved, so they start off every launch.
-- ======================================================================================

local Log = require("Modules/Log")

local Settings = {}

local FILE_NAME = "settings.json"

-- Options that start from their default every launch.
local SESSION_ONLY = {
    forceVehicleDilation = true,
}

-- Fields of mod.ui that are saved alongside mod.settings.
local UI_KEYS = { "durationVal", "durationUnit" }

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

--- Records the current values as defaults. Call once, before Load.
function Settings.Init(mod)
    mod.defaults = copy(mod.settings)
    mod.uiDefaults = {}
    for _, k in ipairs(UI_KEYS) do mod.uiDefaults[k] = mod.ui[k] end
end

--- Copies saved values over the defaults. A key the defaults do not have, or a value
--- of a different type, is ignored, so a stale or hand-edited file cannot add state.
function Settings.Load(mod, Core)
    local file = io.open(FILE_NAME, "r")
    if not file then return end
    local content = file:read("*a")
    file:close()

    local ok, data = pcall(json.decode, content)
    if not ok or type(data) ~= "table" then
        Log.Warn("settings.json could not be read, using defaults")
        return
    end

    if type(data.settings) == "table" then
        for k, v in pairs(data.settings) do
            local default = mod.defaults[k]
            if not SESSION_ONLY[k] and default ~= nil and type(v) == type(default) then
                mod.settings[k] = v
            end
        end
    end

    if type(data.ui) == "table" then
        for _, k in ipairs(UI_KEYS) do
            if type(data.ui[k]) == type(mod.uiDefaults[k]) then mod.ui[k] = data.ui[k] end
        end
    end

    -- A file written before the start time became one value carries the three combo keys.
    if type(data.settings) == "table" and data.settings.startSeconds == nil
        and type(data.settings.comboHour) == "number" then
        local h = data.settings.comboHour + 1
        local isPm = data.settings.comboAmPm == 1
        local hour24 = h
        if h == 12 then hour24 = isPm and 12 or 0 else hour24 = isPm and (h + 12) or h end
        mod.settings.startSeconds = (hour24 * 3600) + ((data.settings.comboMinute or 0) * 60)
        Log.Debug("Start time migrated to %d seconds", mod.settings.startSeconds)
    end

    if not Log.IsLevel(mod.settings.logLevel) then mod.settings.logLevel = mod.defaults.logLevel end
    Core.ClampSpeed(mod)
    Core.RecalcDuration(mod)
end

function Settings.Save(mod)
    local saved = {}
    for k, v in pairs(mod.settings) do
        if not SESSION_ONLY[k] then saved[k] = v end
    end
    local ui = {}
    for _, k in ipairs(UI_KEYS) do ui[k] = mod.ui[k] end

    local ok, content = pcall(json.encode, { settings = saved, ui = ui })
    if not ok then return end

    local file = io.open(FILE_NAME, "w")
    if not file then return end
    file:write(content)
    file:close()
end

return Settings
