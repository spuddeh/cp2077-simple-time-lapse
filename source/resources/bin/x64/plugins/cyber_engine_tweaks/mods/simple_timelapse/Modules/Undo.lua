-- ======================================================================================
-- Simple Time-lapse - Undo Module
-- Mod Version: 2.0.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- The list of changes the current run made. Each change records how to put back the
-- value it replaced; one call runs them all, newest first, on Stop, session end and
-- shutdown. A change the run did not make has no entry, so it is never "restored".
-- ======================================================================================

local Log = require("Modules/Log")

local Undo = {}
local entries = {}

--- Records how to undo one change. `restore` runs once, and should leave the value
--- alone if something else has changed it since the run wrote it.
function Undo.Push(name, restore)
    entries[#entries + 1] = { name = name, restore = restore }
end

--- True while the current run has an entry with this name.
function Undo.Has(name)
    for _, entry in ipairs(entries) do
        if entry.name == name then return true end
    end
    return false
end

--- Runs every entry, newest first, and empties the list. One failing entry does not stop the rest.
function Undo.RunAll()
    local list = entries
    entries = {}
    for i = #list, 1, -1 do
        local ok, err = pcall(list[i].restore)
        if ok then
            Log.Debug("Undone: %s", list[i].name)
        else
            Log.Error("Could not undo %s: %s", list[i].name, tostring(err))
        end
    end
end

return Undo
