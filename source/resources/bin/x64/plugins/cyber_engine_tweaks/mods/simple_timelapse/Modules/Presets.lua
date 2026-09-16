-- ======================================================================================
-- Simple Time-lapse - Presets Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Named shot recipes in presets.json. A preset holds every setting except the ones that
-- belong to the session rather than the shot: the log level, and Traffic Frenzy with its
-- speed. Loading one copies values that match a default by name and type, so a preset
-- written by an older version cannot add state or change a type.
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

-- name -> { settings = {...}, ui = {...} }, in load order.
local presets = {}
local order = {}

local function Write()
    local out = {}
    for i, name in ipairs(order) do
        out[i] = { name = name, settings = presets[name].settings, ui = presets[name].ui }
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
    presets = {}
    order = {}

    local file = io.open(FILE_NAME, "r")
    if not file then return end
    local content = file:read("*a")
    file:close()

    local ok, data = pcall(json.decode, content)
    if not ok or type(data) ~= "table" or type(data.presets) ~= "table" then
        Log.Warn("presets.json could not be read, starting with none")
        return
    end

    for _, entry in ipairs(data.presets) do
        if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
            presets[entry.name] = {
                settings = type(entry.settings) == "table" and entry.settings or {},
                ui = type(entry.ui) == "table" and entry.ui or {},
            }
            order[#order + 1] = entry.name
        end
    end
    Log.Debug("Presets loaded: %d", #order)
end

--- Preset names, in the order they were saved.
function Presets.Names()
    return order
end

function Presets.Exists(name)
    return presets[name] ~= nil
end

--- Saves the current settings under `name`, replacing a preset of that name.
function Presets.Save(mod, name)
    if type(name) ~= "string" or name == "" then return false end

    local settings = {}
    for k, v in pairs(mod.settings) do
        if not EXCLUDED[k] then settings[k] = v end
    end
    local ui = {}
    for _, k in ipairs(UI_KEYS) do ui[k] = mod.ui[k] end

    if not presets[name] then order[#order + 1] = name end
    presets[name] = { settings = settings, ui = ui }
    Write()
    Log.Info("Preset saved: %s", name)
    return true
end

--- Copies a preset over the current settings. A key the defaults do not have, or a value
--- of a different type, is ignored.
function Presets.Apply(mod, name, Core)
    local preset = presets[name]
    if not preset then return false end

    for k, v in pairs(preset.settings) do
        local default = mod.defaults[k]
        if not EXCLUDED[k] and default ~= nil and type(v) == type(default) then
            mod.settings[k] = v
        end
    end
    for _, k in ipairs(UI_KEYS) do
        if type(preset.ui[k]) == type(mod.uiDefaults[k]) then mod.ui[k] = preset.ui[k] end
    end

    Core.ClampSpeed(mod)
    Core.RecalcDuration(mod)
    Log.Info("Preset loaded: %s", name)
    return true
end

function Presets.Delete(name)
    if not presets[name] then return false end
    presets[name] = nil
    for i, entry in ipairs(order) do
        if entry == name then
            table.remove(order, i)
            break
        end
    end
    Write()
    Log.Info("Preset deleted: %s", name)
    return true
end

return Presets
