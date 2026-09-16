-- ======================================================================================
-- Simple Time-lapse - Notifications Module
-- Mod Version: 1.3.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Silences the on-screen notification queues for the length of a run: messages, journal
-- and quest updates, and the generic side popups. The popup still appears; only its
-- sound is suppressed, and only for queues this mod silenced. A phone call is not one of
-- these queues - PhoneSystem plays its ringtone straight through the audio system.
-- ======================================================================================

local Log = require("Modules/Log")
local Undo = require("Modules/Undo")

local Notifications = {}

-- GenericNotificationType members, one per notification queue with its own sound.
local QUEUES = { "Generic", "JournalNotification", "PhoneNotification" }

local function Send(queue, silent)
    local ui = Game.GetUISystem()
    if not ui then return end
    local evt = MakeNotificationQueueSilentEvent.new()
    evt.notificationType = Enum.new("GenericNotificationType", queue)
    evt.makeSilent = silent
    ui:QueueEvent(evt)
end

local function SetAll(silent)
    for _, queue in ipairs(QUEUES) do Send(queue, silent) end
end

--- Silences the queues for the run, and records the undo that gives them back.
function Notifications.Silence(mod)
    if not mod.settings.muteNotifications then return end
    SetAll(true)
    Log.Debug("Notification queues silenced")
    Undo.Push("notifications", function() SetAll(false) end)
end

--- Panic button: gives every queue its sound back, whether or not this mod took it.
function Notifications.ForceRestore()
    SetAll(false)
    Log.Debug("Notification queues audible again")
end

return Notifications
