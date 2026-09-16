-- ======================================================================================
-- Simple Time-lapse - Presets Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Named shot recipes. Four ship with the mod and are always in the list; the rest are
-- the player's, saved to presets.json. A preset holds every setting except the ones
-- that belong to the session rather than the shot: the log level, and Traffic Frenzy
-- with its speed. Loading one copies values that match a default by name and type, so
-- a preset written by an older version cannot add state or change a type.
--
-- A saved preset may take a shipped preset's name. It shadows it in the list, and
-- deleting it brings the shipped one back.
-- ======================================================================================

local Log = require("Modules/Log")

local Presets = {}

local FILE_NAME = "presets.json"

-- Settings a preset never carries.
local EXCLUDED = {
    logLevel = true,
    forceVehicleDilation = true,
    frenzySpeedMult = true,
}

-- Fields of mod.ui a preset carries, because duration is built from them.
local UI_KEYS = { "durationVal", "durationUnit" }

-- The shipped recipes. Each lists only what it changes; everything else comes from the
-- mod's defaults, so a shipped preset always describes a whole shot.
local BUILTIN = {
    {
        name = "Defaults",
        settings = {},
        ui = {},
    },
    {
        name = "Sunrise",
        settings = { mode = 1, speed = 600.0, useStartTime = true, startSeconds = 18000.0 },
        ui = { durationVal = 60.0, durationUnit = 0 },
    },
    {
        name = "City Rush",
        settings = { mode = 0, speed = 10.0, useStartTime = true, startSeconds = 63000.0 },
        ui = { durationVal = 2.0, durationUnit = 1 },
    },
    {
        name = "Empty City",
        settings = { mode = 0, speed = 10.0, disableCrowds = true, disableAirTraffic = true },
        ui = { durationVal = 2.0, durationUnit = 1 },
    },
}

-- name -> { settings = {...}, ui = {...} } for the player's own, in save order.
local saved = {}
local savedOrder = {}

-- Every name on offer: the shipped ones first, then the player's.
local order = {}

local function IsBuiltinName(name)
    for _, preset in ipairs(BUILTIN) do
        if preset.name == name then return true end
    end
    return false
end

local function BuiltinByName(name)
    for _, preset in ipairs(BUILTIN) do
        if preset.name == name then return preset end
    end
    return nil
end

--- A saved preset of the same name shadows the shipped one, so each name appears once.
local function RebuildOrder()
    order = {}
    for _, preset in ipairs(BUILTIN) do
        order[#order + 1] = preset.name
    end
    for _, name in ipairs(savedOrder) do
        if not IsBuiltinName(name) then order[#order + 1] = name end
    end
end

local function Write()
    local out = {}
    for i, name in ipairs(savedOrder) do
        out[i] = { name = name, settings = saved[name].settings, ui = saved[name].ui }
    end

    local ok, content = pcall(json.encode, { presets = out })
    if not ok then
        Log.Error("Presets could not be encoded, nothing written")
        return
    end

    local file = io.open(FILE_NAME, "w")
    if not file then
        Log.Error("presets.json could not be opened for writing")
        return
    end
    file:write(content)
    file:close()
end

function Presets.Load()
    saved = {}
    savedOrder = {}

    local file = io.open(FILE_NAME, "r")
    if file then
        local content = file:read("*a")
        file:close()

        local ok, data = pcall(json.decode, content)
        if ok and type(data) == "table" and type(data.presets) == "table" then
            for _, entry in ipairs(data.presets) do
                if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
                    saved[entry.name] = {
                        settings = type(entry.settings) == "table" and entry.settings or {},
                        ui = type(entry.ui) == "table" and entry.ui or {},
                    }
                    savedOrder[#savedOrder + 1] = entry.name
                end
            end
        else
            Log.Warn("presets.json could not be read, only the shipped presets are available")
        end
    end

    RebuildOrder()
    Log.Debug("Presets: %d shipped, %d saved", #BUILTIN, #savedOrder)
end

--- Every preset name, shipped first.
function Presets.Names()
    return order
end

--- True while the name belongs to a shipped preset no saved preset has taken over.
function Presets.IsBuiltin(name)
    return IsBuiltinName(name) and saved[name] == nil
end

--- Saves the current settings under `name`, replacing a saved preset of that name.
function Presets.Save(mod, name)
    if type(name) ~= "string" or name == "" then return false end

    local settings = {}
    for k, v in pairs(mod.settings) do
        if not EXCLUDED[k] then settings[k] = v end
    end
    local ui = {}
    for _, k in ipairs(UI_KEYS) do ui[k] = mod.ui[k] end

    if not saved[name] then savedOrder[#savedOrder + 1] = name end
    saved[name] = { settings = settings, ui = ui }
    RebuildOrder()
    Write()
    Log.Info("Preset saved: %s", name)
    return true
end

local function CopyInto(mod, settings, ui)
    for k, v in pairs(settings) do
        local default = mod.defaults[k]
        if not EXCLUDED[k] and default ~= nil and type(v) == type(default) then
            mod.settings[k] = v
        end
    end
    for _, k in ipairs(UI_KEYS) do
        if type(ui[k]) == type(mod.uiDefaults[k]) then mod.ui[k] = ui[k] end
    end
end

--- Copies a preset over the current settings. A shipped preset resets everything it does
--- not name back to the mod's defaults, so it always gives the same shot.
function Presets.Apply(mod, name, Core)
    local preset = saved[name]
    if preset then
        CopyInto(mod, preset.settings, preset.ui)
    else
        local builtin = BuiltinByName(name)
        if not builtin then return false end
        CopyInto(mod, mod.defaults, mod.uiDefaults)
        CopyInto(mod, builtin.settings, builtin.ui)
    end

    Core.ClampSpeed(mod)
    Core.RecalcDuration(mod)
    Log.Info("Preset loaded: %s", name)
    return true
end

--- Deletes a saved preset. A shipped preset cannot be deleted; deleting one that shadows
--- a shipped name brings the shipped preset back.
function Presets.Delete(name)
    if not saved[name] then return false end
    saved[name] = nil
    for i, entry in ipairs(savedOrder) do
        if entry == name then
            table.remove(savedOrder, i)
            break
        end
    end
    RebuildOrder()
    Write()
    Log.Info("Preset deleted: %s", name)
    return true
end

return Presets
