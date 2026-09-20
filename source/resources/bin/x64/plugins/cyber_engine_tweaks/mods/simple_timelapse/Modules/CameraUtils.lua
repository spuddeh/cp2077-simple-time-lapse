-- ======================================================================================
-- Simple Time-lapse - CameraUtils Module
-- Mod Version: 2.0.0
-- Author:       Spuddeh
--
-- DESCRIPTION:
-- Handles Head Bobbing (Additive Camera Motions) via GameSettings.
-- Handles Player Movement/Look Locking via Status Effects.
-- ======================================================================================

local GameSettings = require("Modules/GameSettings")
local Log = require("Modules/Log")
local Undo = require("Modules/Undo")
local CameraUtils = {}

-- The game setting that controls additive camera movement (head bob / sway).
local CAMERA_PATH = "/accessibility/difficulty/AdditiveCameraMovements"

-- Helper to get IDs safely at runtime
local function GetRestrictionIDs()
    return {
        MOVE = TweakDBID.new("GameplayRestriction.NoMovement"),
        LOOK = TweakDBID.new("GameplayRestriction.NoCameraControl"),
        COMBAT = TweakDBID.new("GameplayRestriction.NoCombat")
    }
end

-- =================================================================
-- ### HEAD BOBBING ###
-- =================================================================

local function IsZero(value)
    return value ~= nil and math.abs(value) < 0.001
end

function CameraUtils.Disable()
    local success, before = pcall(function() return GameSettings.Get(CAMERA_PATH) end)
    if not success or before == nil then
        Log.Warn("Could not read %s, head bob left unchanged", CAMERA_PATH)
        return
    end
    if IsZero(before) then return end

    GameSettings.Set(CAMERA_PATH, 0.0)
    Log.Debug("Head bob disabled")
    Undo.Push("headBob", function()
        if IsZero(GameSettings.Get(CAMERA_PATH)) then GameSettings.Set(CAMERA_PATH, before) end
    end)
end

function CameraUtils.ForceRestore(mod)
    pcall(function() GameSettings.Set(CAMERA_PATH, 1.0) end)
    Log.Debug("Head bob forced to 1.0")
end

-- =================================================================
-- ### PLAYER LOCKING ###
-- =================================================================

function CameraUtils.LockPlayer(mod)
    local player = Game.GetPlayer()
    if not player then return end
    local ses = Game.GetStatusEffectSystem()
    if not ses then return end
    local entityID = player:GetEntityID()

    local ids = GetRestrictionIDs()

    -- A restriction the player already has belongs to whatever applied it, and is left on.
    local function Lock(name, id)
        if ses:HasStatusEffect(entityID, id) then return end
        ses:ApplyStatusEffect(entityID, id)
        Undo.Push(name, function()
            local p = Game.GetPlayer()
            local s = Game.GetStatusEffectSystem()
            if p and s then s:RemoveStatusEffect(p:GetEntityID(), id) end
        end)
    end

    if mod.settings.lockMovement then
        Lock("lockMovement", ids.MOVE)
    end

    -- NoCombat empties the player's hands, which is also what silences the Radioport.
    if mod.settings.lockWeapons then
        Lock("lockWeapons", ids.COMBAT)
    end

    if mod.settings.lockCamera then
        Lock("lockCamera", ids.LOOK)
    end
end

function CameraUtils.UnlockMovement(mod)
    local player = Game.GetPlayer(); if not player then return end
    local ses = Game.GetStatusEffectSystem(); if not ses then return end
    local entityID = player:GetEntityID()

    local ids = GetRestrictionIDs()
    ses:RemoveStatusEffect(entityID, ids.MOVE)
    ses:RemoveStatusEffect(entityID, ids.COMBAT)
    Log.Debug("Movement unlocked")
end

function CameraUtils.UnlockCamera(mod)
    local player = Game.GetPlayer(); if not player then return end
    local ses = Game.GetStatusEffectSystem(); if not ses then return end

    local ids = GetRestrictionIDs()
    ses:RemoveStatusEffect(player:GetEntityID(), ids.LOOK)
    Log.Debug("Camera unlocked")
end

return CameraUtils
